--
-- https://github.com/Lougous/b68k-av
--
-- frame buffer read-back
--

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity rb is

  port (
    RSTn  : in    std_logic;
    CLK25 : in    std_logic;

    -- configuration registers
    REG_BUFFER   : in std_logic;
    REG_BASE     : in std_logic_vector(16 downto 0);
    REG_LOWRES   : in std_logic;
    REG_LUT_PAGE : in std_logic;

    -- video timing
    TOP_FRAME : in std_logic;
    TOP_LINE  : in std_logic;
    TOP_EO2L  : in std_logic;
    EVEN_LINE : in std_logic;
    RB_ENABLE : in std_logic;
    HCNT      : in std_logic_vector(9 downto 0);
    
    -- memory
    AD    : out std_logic_vector(18 downto 0);
    RE    : out std_logic;
    RDT   : in std_logic_vector(15 downto 0);
    RACK  : in std_logic;

    -- pixels out
    PCLK : out std_logic;
    PDAT : out std_logic_vector(7 downto 0)
    );

end entity rb;

architecture rtl of rb is

  signal RE_i : std_logic;
  
  signal pxl_buffer   : std_logic;
  signal pxl_addr     : std_logic_vector(16 downto 0);
  signal pxl_sr       : std_logic_vector(15 downto 0);
  signal pxl_to_mixer : std_logic_vector(7 downto 0);

  signal even_d : std_logic;
  
begin
  
  AD <= pxl_buffer & "1" & pxl_addr;
  RE <= RE_i and not RACK;
  
  ------------------------------------------------------------------------------
  -- address/memory accesses
  ------------------------------------------------------------------------------
  fetch_p: process (CLK25, RSTn) is
  begin
    if RSTn = '0' then
      RE_i <= '0';

      pxl_buffer   <= '0';
      pxl_addr     <= (others => '0');
      pxl_sr       <= (others => '0');

    elsif rising_edge(CLK25) then

      if HCNT(0) = '1' then
        pxl_sr <= x"00" & pxl_sr(15 downto 8);
      end if;

      -- X address
      if RACK = '1' then
        RE_i <= '0';
        pxl_sr <= RDT;
        pxl_addr(8 downto 0) <= std_logic_vector(unsigned(pxl_addr(8 downto 0)) + 2);
      end if;

      if TOP_LINE = '1' then
        pxl_addr(8 downto 0)  <= (others => '0');
      end if;
 
      -- Y address
      if TOP_EO2L = '1' then
        pxl_addr(16 downto 9) <= std_logic_vector(unsigned(pxl_addr(16 downto 9)) + 1);
      end if;

      -- frame reset
      if TOP_FRAME = '1' then
        pxl_buffer <= REG_BUFFER;
        pxl_addr   <= REG_BASE;
      end if;

      if RB_ENABLE = '1' and HCNT(1 downto 0) = "00" then
        RE_i <= '1';
      end if;
      
    end if;
  end process fetch_p;

  pxl_to_mixer <= pxl_sr(7 downto 0);
  
  ------------------------------------------------------------------------------
  -- video mixer
  ------------------------------------------------------------------------------
  mix_p: process (CLK25, RSTn) is
    variable pxl : std_logic;
    
  begin
    if RSTn = '0' then
      PDAT <= (others => '0');
      
    elsif rising_edge(CLK25) then

      if REG_LOWRES = '1' then
        PDAT <= pxl_to_mixer;
      else
        -- mixed mode
        if pxl_to_mixer(7) = '0' then
          -- low res pixel
          PDAT <= pxl_to_mixer;
        else
          -- hi res pixels
          -- select pixel in 4x1 tile
          
          if HCNT(0) = '0' then
            if EVEN_LINE = '1' then
              pxl := pxl_to_mixer(0);
            else
              pxl := pxl_to_mixer(2);
            end if;
          else
            if EVEN_LINE = '1' then
              pxl := pxl_to_mixer(1);
            else
              pxl := pxl_to_mixer(3);
            end if;
          end if;
          
          PDAT <= '1' & REG_LUT_PAGE & pxl_to_mixer(6 downto 4) & (EVEN_LINE) & HCNT(0) & pxl;
        end if;
      end if;
          
    end if;
  end process mix_p;

  PCLK <= not CLK25;  -- TODO: phase to adjust

end architecture rtl;
