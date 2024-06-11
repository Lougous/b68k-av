--
-- https://github.com/Lougous/b68k-av
--
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity avmgr is

  port (

    -- local clocks
    CLK25   : in  std_logic;
    CLK3P58 : out std_logic;

    -- extension bus
    B_RSTn : in    std_logic;
    B_CEn  : in    std_logic;
    B_WEn  : in    std_logic;
    B_ACKn : inout std_logic;
    B_ALEn : in    std_logic;

    -- spare, to GPIO connector
    GP     : out std_logic_vector(2 downto 0);

    -- flex conf
    FLEX_DCLK : out std_logic;
    FLEX_DAT0 : out std_logic;
    FLEX_nCFG : out std_logic;
    FLEX_CFD  : in  std_logic;
    FLEX_nSTS : in  std_logic;

    -- local bus
    L_A    : out   std_logic_vector(1 downto 0);
    L_AD7  : inout std_logic;
    L_AD6  : inout std_logic;
    L_AD1  : inout std_logic;
    L_AD0  : inout std_logic;
    L_RSTn : out   std_logic;

    G_OEn : out   std_logic;  -- AD bus driver output enable
    G_DIR : out   std_logic;  -- AD bus driver direction 
    
    -- OPL2
    OPL2_CEn : out std_logic;
    OPL2_WEn : out std_logic;
    OPL2_REn : out std_logic;

    -- RAMDAC
    DAC_WEn : out std_logic;
    DAC_REn : out std_logic;

    -- flex
    FLEX_WEn : out std_logic;
    FLEX_REn : out std_logic

    );

end entity avmgr;

architecture rtl of avmgr is

  signal clk3p58_cnt : unsigned(2 downto 0) := (others => '0');

  signal b_a_hi : std_logic_vector(3 downto 0);

  signal l_cs_n    : std_logic;
  signal flex_cs_n : std_logic;
  signal dac_cs_n  : std_logic;
  signal opl2_cs_n : std_logic;

  signal write_valid : std_logic;
  signal re_n : std_logic;
  signal we_n : std_logic;

  signal l_re_n    : std_logic;
  signal l_reg_sel : std_logic_vector(1 downto 0);

  signal ce_n_meta  : std_logic;
  signal ce_n       : std_logic;
  signal ce_n_delay : std_logic;

  signal early_ack : std_logic;

  signal GP_reg        : std_logic_vector(2 downto 0);
  signal FLEX_DCLK_sr  : std_logic_vector(2 downto 0);
  signal FLEX_DAT0_reg : std_logic;
  signal FLEX_nCFG_reg : std_logic;
  signal L_RSTn_reg    : std_logic;

  type fsm_t is (S_IDLE, S_WS4, S_WS3, S_WS2, S_WS1, S_ACK);
  signal fsm : fsm_t;

  
begin  -- architecture rtl

  ------------------------------------------------------------------------------
  -- generates clock for OPL2
  -- 25MHz / 7 = 3.571428571 MHz
  -- duty cycle: 4/7 - 3/7
  ------------------------------------------------------------------------------
  process (CLK25) is
  begin
    if rising_edge(CLK25) then
      clk3p58_cnt <= clk3p58_cnt + 1;

      if clk3p58_cnt = 6 then
        clk3p58_cnt <= (others => '0');
      end if;
      
    end if;
  end process;

  CLK3P58 <= clk3p58_cnt(2);


  ------------------------------------------------------------------------------
  -- bus address latch
  ------------------------------------------------------------------------------
  process (B_ALEn) is
  begin
    if rising_edge(B_ALEn) then
      b_a_hi <= b_a_hi(1 downto 0) & L_AD7 & L_AD6;

      l_reg_sel <= L_AD1 & L_AD0;
    end if;
  end process;

  -- to OPL2 and RAMDAC chips
  -- (flex has B_ALEn and B_A0)
  L_A <= l_reg_sel;

  
  ------------------------------------------------------------------------------
  -- address decoding
  ------------------------------------------------------------------------------

  -- address mapping
  --
  --  B_A(7..6)  B_A(7..6)  user @   chip
  --    00         00           0h   avmgr (me !)
  --    00         01          80h   flex
  --    00         10         100h   RAMDAC
  --    00         00         180h   OPL2
  --    01         xx        8000h   flex
  --    10         xx       10000h   flex
  --    11         xx       18000h   flex

  -- avmgr: address = "00-00"
  l_cs_n    <= '0' when b_a_hi = "0000" else '1';

  -- flex: address = "01"
  flex_cs_n <= '0' when b_a_hi(3 downto 2) = "01" else  -- VRAM bank 1
               '0' when b_a_hi(3 downto 2) = "10" else  -- VRAM bank 2
               '0' when b_a_hi(3 downto 2) = "11" else  -- VRAM bank 3
               '0' when b_a_hi = "0001"           else  -- FLEX registers
               '1';
  
  -- ramdac: address = "10"
  dac_cs_n <= '0' when b_a_hi = "0010" else '1';
  
  -- opl2: address = "11"
  opl2_cs_n <= '0' when b_a_hi = "0011" else '1';

  ------------------------------------------------------------------------------
  -- chips read/write control
  ------------------------------------------------------------------------------
  re_n <= (not B_WEn) or B_CEn or ce_n_delay;
  we_n <= B_WEn or B_CEn or (not write_valid);

  DAC_REn  <= dac_cs_n or re_n;
  DAC_WEn  <= dac_cs_n or we_n;

  OPL2_CEn <= opl2_cs_n or (re_n and we_n);
  OPL2_REn <= opl2_cs_n or re_n;
  OPL2_WEn <= opl2_cs_n or we_n;

  FLEX_REn <= flex_cs_n or re_n;
  FLEX_WEn <= flex_cs_n or we_n;

  l_re_n <= l_cs_n or re_n;
  
  ------------------------------------------------------------------------------
  -- data read
  ------------------------------------------------------------------------------
  L_AD7 <= L_RSTn_reg    when l_re_n = '0' and l_reg_sel = "00" else
           '0'           when l_re_n = '0' and l_reg_sel = "01" else
           GP_reg(2)     when l_re_n = '0' and l_reg_sel = "10" else
--           GP(2)         when l_re_n = '0' and l_reg_sel = "11" else
           '0'           when l_re_n = '0' and l_reg_sel = "11" else
           'Z';

  L_AD6 <= FLEX_nCFG_reg when l_re_n = '0' and l_reg_sel = "00" else
           '0'           when l_re_n = '0' and l_reg_sel = "01" else
           '0'           when l_re_n = '0' and l_reg_sel = "10" else
           '0'           when l_re_n = '0' and l_reg_sel = "11" else
           'Z';
  
  L_AD1 <= FLEX_CFD      when l_re_n = '0' and l_reg_sel = "00" else
           '0'           when l_re_n = '0' and l_reg_sel = "01" else
           GP_reg(1)     when l_re_n = '0' and l_reg_sel = "10" else
--           GP(1)         when l_re_n = '0' and l_reg_sel = "11" else
           '0'           when l_re_n = '0' and l_reg_sel = "11" else
           'Z';

  L_AD0 <= FLEX_nSTS     when l_re_n = '0' and l_reg_sel = "00" else
           FLEX_DAT0_reg when l_re_n = '0' and l_reg_sel = "01" else
           GP_reg(0)     when l_re_n = '0' and l_reg_sel = "10" else
--           GP(0)         when l_re_n = '0' and l_reg_sel = "11" else
           '0'           when l_re_n = '0' and l_reg_sel = "11" else
           'Z';


  ------------------------------------------------------------------------------
  -- sequencer
  ------------------------------------------------------------------------------
  -- write access to FLEX
  early_ack <= B_CEn or flex_cs_n or we_n;

  B_ACKn <= '0' when (early_ack = '0') or (fsm = S_ACK) else 'Z';

  G_OEn  <= '0';
  
  G_DIR <= '1' when B_WEn = '1' and ce_n = '0' else  -- read
           '0';  -- 0: bus -> AV

  process (CLK25) is
  begin
    if rising_edge(CLK25) then
      -- CDC FF
      ce_n_meta <= B_CEn;
    end if;
  end process;

  process (CLK25) is
  begin
    if falling_edge(CLK25) then
      ce_n <= ce_n_meta;
    end if;
  end process;

 
  process (B_RSTn, CLK25) is
  begin
    if B_RSTn = '0' then
      GP_reg        <= (others => '0');
      FLEX_DCLK_sr  <= "000";
      FLEX_DAT0_reg <= '1';
      FLEX_nCFG_reg <= '1';
      L_RSTn_reg    <= '0';
      write_valid   <= '1';

    elsif rising_edge(CLK25) then

      ce_n_delay <= ce_n;

      FLEX_DCLK_sr <= '0' & FLEX_DCLK_sr(2 downto 1);

      case fsm is
        when S_IDLE =>
          -- wait for access
          write_valid <= '1';

          -- start with B_CEn falling edge
          if ce_n = '0' and ce_n_delay = '1' then
            if dac_cs_n = '0' then
              -- minimum read/write pulse 50ns, ACK => CE is at least 50ns
              fsm <= S_WS1;
            elsif opl2_cs_n = '0' then
              if B_WEn = '0' then
                -- minimum write pulse 100 ns, ACK => CE is at least 50ns
                fsm      <= S_WS1;
              else
                -- minimum read pulse 200 ns
                fsm      <= S_WS4;
              end if;
              
            elsif flex_cs_n = '0' then
              fsm      <= S_WS1;
              --if B_WEn = '0' then
              --  fsm      <= S_WS1;
              --else
              --  fsm      <= S_ACK;
              --end if;
            else
              -- me
              if B_WEn = '0' then
                -- write
                if l_reg_sel = "00" then
                  FLEX_nCFG_reg <= L_AD6;
                  L_RSTn_reg <= L_AD7;
                elsif l_reg_sel = "01" then
                  FLEX_DAT0_reg <= L_AD0;
                  FLEX_DCLK_sr <= "110";

                elsif l_reg_sel = "10" then
                  GP_reg <= L_AD7 & L_AD1 & L_AD0;
                else
                  -- read only
                  null;
                end if;
              end if;
              
              fsm <= S_ACK;
            end if;
          end if;

        when S_WS4 =>
          fsm <= S_WS3;
          
        when S_WS3 =>
          fsm <= S_WS2;
          
        when S_WS2 =>
          fsm <= S_WS1;

        when S_WS1 =>
          fsm <= S_ACK;

        when S_ACK =>
          write_valid <= '0';
          
          if ce_n = '1' then
            fsm <= S_IDLE;
          end if;

        when others => null;
      end case;

    end if;
  end process;

  GP(0) <= GP_reg(0);
  GP(1) <= ce_n_meta;
--  GP(2) <= opl2_cs_n;

  process (CLK25) is
  begin
    if falling_edge(CLK25) then
      GP(2) <= B_CEn;
    end if;
  end process;


  FLEX_DCLK <= FLEX_DCLK_sr(0);
  FLEX_DAT0 <= FLEX_DAT0_reg;
  FLEX_nCFG <= FLEX_nCFG_reg;

  -- connected to flex only
  L_RSTn <= L_RSTn_reg;

end architecture rtl;
