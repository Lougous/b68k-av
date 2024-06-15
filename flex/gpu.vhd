--
-- https://github.com/Lougous/b68k-av
--
-- graphic processing unit
--
-- register mapping
--  +00 : stop display list in progress if any and set display list address bits (8:1)
--  +01 : set display list address bits (16:9) and start display list
--
-- Display lists execute in lower 128-kiB in VRAM (00000h to 1FFFFh)
--
-- Display lists commands
--  15 | 14 | 13 | 12 | 11 | 10 |  9 |  8 |  7 |  6 |  5 |  4 |  3 |  2 |  1 |  0 |
--   0 |                               ADDR(14:0)                                 |
--   1 |  0 |  - |    ADDR(18:15)    |  S |    HEIGHT(3:0)    |  F | LR | LP | WS |
--   1 |  1 |  - |    WIDTH(3:0)     | RW | KY | -  | BK(3:0) |      LUT(3:0)     |
--
--  ADDR:   VRAM address to read/write, or to set as frame buffer start address
--  S:      stop display list execution when set
--  F:      set frame buffer address/attributes when set
--  LR:     Low res mode (validated by F)
--  LP:     LUT in hi res mode (validated by F)
--  WS:     when set with S, wait for next vertical synchro then restart
--          display list execution
--  HEIGHT: pixel block height (line number, minus 1)
--  WIDTH:  pixel block width (word number, minus 1)
--  LUT:    pixel byte bits(7:4) for write (4-bits to 8-bits expansion)
--  BK:     256 bytes scratchpad start address MSBs (00h, 40h, 80h, C0h)
--  KY:     enable transparency during write with color key 0000b
--  RW:     transfer direction: 0 for VRAM to scratchpad, 1 for scratchpad to VRAM
--
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity gpu is

  port (
    RSTn  : in    std_logic;
    CLK25 : in    std_logic;

    -- local bus
    LWE   : in std_logic;
    LA    : in std_logic;
    LD    : in std_logic_vector(7 downto 0);
    BUSY  : out std_logic;

    -- read back config
    RB_BUFFER   : out std_logic;
    RB_BASE     : out std_logic_vector(16 downto 0);
    RB_LOWRES   : out std_logic;
    RB_LUT_PAGE : out std_logic;

    -- external vertical timing synchro
    VS : in std_logic;
    
    -- memory
    WE    : out std_logic;
    RE    : out std_logic;
    AD    : out std_logic_vector(18 downto 0);
    WDT   : out std_logic_vector(15 downto 0);
    WM    : out std_logic_vector(1 downto 0);
    ACK   : in std_logic;
    WDACK : in std_logic;
    RDT   : in std_logic_vector(15 downto 0);
    RDACK : in std_logic
    );

end entity gpu;

architecture rtl of gpu is

  -- scratch memory
  signal sc_ad : std_logic_vector(7 downto 0);
  signal sc_wd : std_logic_vector(7 downto 0);
  signal sc_we : std_logic;
  signal sc_rd : std_logic_vector(7 downto 0);
  
  -- gpu states
  signal regad  : std_logic_vector(18 downto 0);
  signal regsx  : std_logic_vector(3 downto 0);
  signal regsy  : std_logic_vector(3 downto 0);
  signal reglut : std_logic_vector(3 downto 0);
  signal regkey : std_logic;

  -- gpu memory access
  signal mad    : std_logic_vector(18 downto 0);
--  signal mwd    : std_logic_vector(15 downto 0);
  signal mdata  : std_logic_vector(15 downto 0);
--  signal mwe    : std_logic_vector(1 downto 0);

  signal s_idle     : std_logic;
  signal s_start    : std_logic;
  signal s_nextline : std_logic;
  signal s_save_ptr : std_logic;
  signal s_load_ptr : std_logic;

  -- display list
  signal l_ptr : std_logic_vector(15 downto 0);
  signal l_enable : std_logic;

  -- synchro with VS
  signal vs_trig : std_logic;

  signal reading  : std_logic;
  signal writing  : std_logic;
  signal dir      : std_logic;
  signal rack_d   : std_logic;
  signal to_go_x  : std_logic_vector(3 downto 0);
  signal to_go_y  : std_logic_vector(3 downto 0);

  signal RDT_swp : std_logic_vector(15 downto 0);
  
begin

  RDT_swp <= RDT(7 downto 0) & RDT(15 downto 8);
  
  sc_wd <= mdata(7 downto 0);
  
  scratch_i : entity work.scratch
    port map (
      inclock => CLK25,
      address => sc_ad,
      data    => sc_wd,
      we      => sc_we,
      q       => sc_rd
      );
  
  
  AD  <= mad;
  WE  <= writing;  --mwe(0);
  WM(0) <= regkey when sc_rd(3 downto 0) = "0000" else '1';
  WM(1) <= regkey when sc_rd(7 downto 4) = "0000" else '1';
  WDT <= reglut & sc_rd(7 downto 4) & reglut & sc_rd(3 downto 0);
  RE  <= reading;

  BUSY <= l_enable or vs_trig;

  gpu_p: process (CLK25, RSTn) is
  begin
    if RSTn = '0' then
      RB_BUFFER   <= '0';
      RB_BASE     <= (others => '0');
      RB_LOWRES   <= '0';
      RB_LUT_PAGE <= '0';
      
      sc_ad <= (others => '0');
      sc_we <= '0';

      regad  <= (others => '0');
      regsx  <= "0111";  -- 8 pixels
      regsy  <= "1001";  -- 10 pixels
      reglut <= (others => '0');
      regkey <= '0';
      
      mad <= (others => '0');
--      mwe <= (others => '0');
--      mwd <= (others => '0');
      mdata <= (others => '0');

      l_ptr <= (others => '0');
      l_enable <= '0';

      s_idle <= '1';
      s_start <= '0';
      s_nextline <= '0';
      s_save_ptr <= '0';
      s_load_ptr <= '0';
      
      dir <= '0';
      reading <= '0';
      writing <= '0';
      rack_d <= '0';

      vs_trig <= '0';

      to_go_x <= (others => '0');
      to_go_y <= (others => '0');

    elsif rising_edge(CLK25) then

      s_start <= '0';
      s_nextline <= '0';
      s_save_ptr <= '0';
      s_load_ptr <= '0';

      if s_save_ptr = '1' then
        l_ptr <= mad(16 downto 1);  --std_logic_vector(unsigned(l_ptr) + 1);
      end if;

      if s_load_ptr = '1' then
        mad <= "00" & l_ptr & "0";  --std_logic_vector(unsigned(l_ptr) + 1);
      end if;

      if LWE = '1' then
        if LA = '0' then
          l_ptr(7 downto 0) <= LD;
          l_enable <= '0';
        else
          l_ptr(15 downto 8) <= LD;
          l_enable <= '1';

          s_load_ptr <= '1';
        end if;
      end if;

      if vs_trig = '1' and VS = '1' then
        l_enable <= '1';
        vs_trig  <= '0';
      end if;

      if s_idle = '1' then
        reading <= l_enable and not ACK;
      end if;

      if s_idle = '1' then
        sc_ad(5 downto 0) <= (others => '0');
       
        to_go_y <= regsy;
        to_go_x <= regsx;

        if RDACK = '1' then
          ----------------------------------------------------------------------
          -- decode commande word
          ----------------------------------------------------------------------
          -- always latch parameters that come with RW commands (they'll have
          -- to be set anyway)
          sc_ad(7 downto 6) <= RDT_swp(5 downto 4);  -- bank
          reglut <= RDT_swp(3 downto 0);  -- LUT
          regsx  <= RDT_swp(12 downto 9);  -- block width
          regkey <= not RDT_swp(7);        -- transparency with color 0000b
       
          if RDT_swp(15) = '0' then
            -- address LSB
            regad <= "0000" & RDT_swp(14 downto 0);
          else
            -- set attributes

            if RDT_swp(14) = '0' then
              -- setup/stop command
              -- address MSB
              regad(18 downto 15) <= RDT_swp(12 downto 9);

              -- block height
              regsy <= RDT_swp(7 downto 4);
              
              -- stop/nop
              l_enable <= l_enable and not RDT_swp(8);
              reading <= not RDT_swp(8);
              vs_trig <= RDT_swp(8) and RDT_swp(0);

              -- setup frame buffer
              if RDT_swp(3) = '1' then
                RB_BASE(14 downto 0)  <= regad(14 downto 0);
                RB_BASE(16 downto 15) <= RDT_swp(10 downto 9);
                RB_BUFFER             <= RDT_swp(12);
                RB_LOWRES             <= RDT_swp(2);
                RB_LUT_PAGE           <= RDT_swp(1);
              end if;
              
            else
              -- block move command (read/write)
              dir <= RDT_swp(8);
              s_idle <= '0';
              s_start <= '1';
              s_save_ptr <= '1';
              reading <= '0';
            end if; 
          end if;

        end if;

      end if;

      if s_start = '1' then
        writing <= dir;
        reading <= not dir;
        to_go_x <= regsx;

        -- update memory address for first access,
        -- then update each line for write
        if s_save_ptr = '1' or dir = '1' then
          mad <= regad;
        end if;

        -- next line +512 bytes
        regad(16 downto 9) <= std_logic_vector(unsigned(regad(16 downto 9)) + 1);
        
--        mwe <= (others => '0');
      end if;

      if s_nextline = '1' then
        to_go_y <= std_logic_vector(unsigned(to_go_y) - 1);

        if to_go_y /= "0000" then
          s_start <= '1';
        else
          s_idle <= '1';
          s_load_ptr <= '1';
        end if;
      end if;

      -- reading
      sc_we <= '0';
      
      if ACK = '1' then
        mad <= std_logic_vector(unsigned(mad) + 2);
      end if;
        
      if RDACK = '1' and s_idle = '0' then
        rack_d <= '1';

        mdata <= RDT;
        sc_we <= '1';

        to_go_x <= std_logic_vector(unsigned(to_go_x) - 1);

        if to_go_x = "0000" then
          s_nextline <= '1';
        end if;
      else
        mdata <= RDT(15 downto 8) & mdata(15 downto 8);
        rack_d <= '0';
      end if;

      if ACK = '1' and to_go_x = "0000" then
        reading <= '0';
      end if;
      
      if rack_d = '1' then
        sc_we <= '1';
      end if;

      if sc_we = '1' then
        sc_ad <= std_logic_vector(unsigned(sc_ad) + 1);
      end if;

     
      -- writing
      if ACK = '1' and to_go_x = "0000" then
        writing <= '0';
      end if;

      if ACK = '1' and writing = '1' then
        sc_ad <= std_logic_vector(unsigned(sc_ad) + 1);
      end if;
      
      if WDACK = '1' then
        --mad <= std_logic_vector(unsigned(mad) + 2); -- TODO: increment low part
                                                    -- only ?
        to_go_x <= std_logic_vector(unsigned(to_go_x) - 1);

        if to_go_x = "0000" then
          --writing <= '0';
          s_nextline <= '1';
        end if;
      end if;

    end if;
  end process gpu_p;

end architecture rtl;
