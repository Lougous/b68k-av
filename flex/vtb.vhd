--
-- https://github.com/Lougous/b68k-av
--
-- video time base (VGA - 640x480@60Hz) 
--

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity vtb is

  port (
    RSTn  : in    std_logic;
    CLK25 : in    std_logic;

    -- sync
    HSYNC     : out std_logic;
    VSYNC     : out std_logic;
    BLANK     : out std_logic;
    VACTIVE   : out std_logic;
    EVEN_LINE : out std_logic;
    RB_ENABLE : out std_logic;
    TOP_FRAME : out std_logic;
    TOP_LINE  : out std_logic;
    TOP_EO2L  : out std_logic;
    TOP_GPU   : out std_logic;
    HCNT      : out std_logic_vector(9 downto 0)
    
    );

end entity vtb;

architecture rtl of vtb is

  signal hcnt_i        : unsigned(9 downto 0);
  signal vcnt          : unsigned(9 downto 0);
  signal had_vsync     : std_logic;
  signal vactive_i     : std_logic;
  signal vid_p0_enable : std_logic;

begin

  BLANK     <= '1';
  VACTIVE   <= vactive_i;
  RB_ENABLE <= vid_p0_enable;
  HCNT      <= std_logic_vector(hcnt_i);
  EVEN_LINE <= vcnt(0);

  vtg_p: process (CLK25, RSTn) is
  begin
    if RSTn = '0' then
      VSYNC <= '0';
      HSYNC <= '0';
      TOP_LINE <= '0';
      TOP_EO2L <= '0';
      TOP_GPU  <= '0';
      
      hcnt_i <= (others => '0');
      vcnt <= (others => '0');
      vactive_i <= '0';
      had_vsync <= '0';

      vid_p0_enable <= '0';
      
      top_frame <= '0';

    elsif rising_edge(CLK25) then

      TOP_LINE <= '0';
      TOP_EO2L <= '0';
      TOP_GPU  <= '0';

      top_frame <= '0';

      hcnt_i <= hcnt_i + 1;

      if hcnt_i(9) = '1' and hcnt_i(8) = '1' and hcnt_i(5) = '1' then
        -- 800 (320h): end of line, front porch => sync
        hcnt_i <= to_unsigned(1, hcnt_i'length);
        HSYNC <= '0';
        TOP_LINE <= '1';
        TOP_EO2L <= vactive_i and not vcnt(0);

        vcnt <= vcnt + 1;
        
        if vcnt(9) = '1' and vcnt(3) = '1' and vcnt(2) = '1' then
          -- 524 (20Ch): end of frame => front porch
          vcnt <= (others => '0');
          top_frame <= '1';
          had_vsync <= '0';
          vactive_i <= '0';
          
          TOP_GPU  <= '1';
        end if;

        if vcnt(3) = '1' and vcnt(0) = '1' and had_vsync = '0' then
          -- 9 (9h): front porch => sync
          VSYNC <= '0';
          had_vsync <= '1';
        end if;
        
        if vcnt(1) = '1' and vcnt(0) = '1' then
          -- 11 (Bh): sync => back porch
          VSYNC <= '1';
        end if;

        if vcnt(5) = '1' and vcnt(3) = '1' and vcnt(2) = '1' then
          -- 44 (2Ch): back porch => active
          vactive_i <= '1';
        end if;
        
      end if;
      
      if hcnt_i(6) = '1' and hcnt_i(5) = '1' then
        -- 96 (60h): sync => back porch
        HSYNC <= '1';

      end if;
       
      if hcnt_i(7) = '1' and hcnt_i(4) = '1' then
        -- 48+96=144 (90h): back porch => active
        vid_p0_enable <= vactive_i;
      end if;
      
      if hcnt_i(9) = '1' and hcnt_i(8) = '1' and hcnt_i(4) = '1' then
        -- 96+48+640=784 (310h): active => front porch
        vid_p0_enable <= '0';
      end if;
      
    end if;
  end process vtg_p;
  

end architecture rtl;
