--
-- https://github.com/Lougous/b68k-av
--
-- OPL2 data decoder
--
-- OPL2 data comes serialized within a 18 clock cycle frame, as defined below:
--                                     _______________________
--  SH  ______________________________/                       \
--
--  MO   X  X  X  X  X  D0 D1 D2 D3 D4 D5 D6 D7 D8 sn S1 S2 S3 
--
--  D0 : LSB
--  sn : sign
--
--  data clock is OPL2 clock divided by 4
--
--  decoding scheme :
--
--    MO data
-- S3 S2 S1 sn             D                   MSB                           LSB
--  1  1  1  1  x  x  x  x  x  x  x  x  x       1 1 x x x x x x x x 0 0 0 0 0 0
--  1  1  0  1  x  x  x  x  x  x  x  x  x       1 0 1 x x x x x x x x 0 0 0 0 0
--  1  0  1  1  x  x  x  x  x  x  x  x  x       1 0 0 1 x x x x x x x x 0 0 0 0
--  1  0  0  1  x  x  x  x  x  x  x  x  x       1 0 0 0 1 x x x x x x x x 0 0 0
--  0  1  1  1  x  x  x  x  x  x  x  x  x       1 0 0 0 0 1 x x x x x x x x 0 0
--  0  1  0  1  x  x  x  x  x  x  x  x  x       1 0 0 0 0 0 1 x x x x x x x x 0
--  0  0  1  1  x  x  x  x  x  x  x  x  x  =>   1 0 0 0 0 0 0 x x x x x x x x x
--  0  0  1  0  x  x  x  x  x  x  x  x  x       0 1 1 1 1 1 1 x x x x x x x x x
--  0  1  0  0  x  x  x  x  x  x  x  x  x       0 1 1 1 1 1 0 x x x x x x x x 0
--  0  1  1  0  x  x  x  x  x  x  x  x  x       0 1 1 1 1 0 x x x x x x x x 0 0
--  1  0  0  0  x  x  x  x  x  x  x  x  x       0 1 1 1 0 x x x x x x x x 0 0 0
--  1  0  1  0  x  x  x  x  x  x  x  x  x       0 1 1 0 x x x x x x x x 0 0 0 0
--  1  1  0  0  x  x  x  x  x  x  x  x  x       0 1 0 x x x x x x x x 0 0 0 0 0
--  1  1  1  0  x  x  x  x  x  x  x  x  x       0 0 x x x x x x x x 0 0 0 0 0 0


library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity opl2_decoder is

  port (
    RSTn  : in  std_logic;
    CLK25 : in  std_logic;
    CLKEQ : out std_logic;

    -- OPL2
    OPL_MO   : in  std_logic;
    OPL_SH   : in  std_logic;
    
    -- audio out
    OPL_TOP_50kHz   : out std_logic;
    OPL_DAT  : out std_logic_vector(15 downto 0)
    );

end entity opl2_decoder;

architecture rtl of opl2_decoder is

  signal clkdiv : std_logic_vector(1 downto 0);
  
  signal opl_cnt7 : std_logic_vector(2 downto 0);
  signal opl_sh_r : std_logic;
  signal opl_top  : std_logic;
  signal opl_sr   : std_logic_vector(15 downto 1);
  signal opl_len  : std_logic;
  signal opl_sign : std_logic;
  signal opl_step : std_logic_vector(2 downto 0);
  signal opl_bin  : std_logic;
  signal opl_nexp : std_logic_vector(3 downto 0);

begin

  clk_div_p: process (CLK25, RSTn) is
  begin
    if RSTn = '0' then
      clkdiv <= (others => '0');
      
    elsif rising_edge(CLK25) then
      clkdiv <= std_logic_vector(unsigned(clkdiv) + 1);

    end if;
  end process clk_div_p;
  
  opl2_top_p: process (CLK25, RSTn) is
  begin
    if RSTn = '0' then
      opl_cnt7 <= "000";
      opl_sh_r <= '0';
      opl_top  <= '0';

      CLKEQ <= '0';
      
    elsif rising_edge(CLK25) then
      -- synchronize with (25/7)/4 clock
      CLKEQ <= '0';
      
      opl_top <= '0';

      if clkdiv = "00" then
        opl_sh_r <= OPL_SH;

        if OPL_SH = '1' and opl_sh_r = '0' then
          opl_cnt7 <= "000";
        elsif opl_cnt7 = "110" then
          -- 6 => 0
          opl_cnt7 <= "000";
        else
          opl_cnt7 <= std_logic_vector(unsigned(opl_cnt7) + 1);
        end if;

        -- generate top around falling edge
        if opl_cnt7 = "010" then
          opl_top <= '1';
        end if;

        CLKEQ <= '1';
      end if;
    end if;
  end process opl2_top_p;

  OPL_DAT <= opl_sign & opl_sr;
  
  opl2_decode_p: process (CLK25, RSTn) is
  begin
    if RSTn = '0' then
      OPL_TOP_50kHz <= '0';
      
      opl_sign  <= '0';
      opl_sr    <= (others => '0');
      opl_step  <= (others => '0');
      opl_len   <= '0';
      opl_bin   <= '0';
      opl_nexp  <= (others => '0');
      
      
    elsif rising_edge(CLK25) then
      
      if opl_nexp(0) = '1' then
        opl_sr <= opl_bin & opl_sr(15 downto 2);
      end if;

      opl_nexp <= '0' & opl_nexp(3 downto 1);
      
      OPL_TOP_50kHz <= '0';
      
      if opl_top = '1' then

        opl_bin  <= '0';
            
        if opl_len = '1' then
          OPL_TOP_50kHz <= '1';
          opl_len <= '0';
        end if;

        opl_step <= std_logic_vector(unsigned(opl_step) + 1);

        case to_integer(unsigned(opl_step)) is
          when 0 =>
            -- D0 to D5
            opl_nexp <= "0001";
            opl_bin  <= OPL_MO;

            -- D5 => D6 when OPL_SH is set
            if OPL_SH = '0' then
              opl_step <= (others => '0');
            end if;

          when 1 | 2 | 3 =>
            -- D6 to D8
            opl_nexp <= "0001";
            opl_bin  <= OPL_MO;

          when 4 =>
            -- D9
            opl_sign <= OPL_MO;
            opl_sr(6 downto 1) <= (others => '0');
            
          when 5 =>
            -- S0
            opl_bin <= not opl_sign;
            
            if OPL_MO = '0' then
              opl_nexp <= "0001";
            else
              opl_nexp <= "0000";
            end if;

          when 6 =>
            -- S1
            opl_bin <= not opl_sign;
            
            if OPL_MO = '0' then
              opl_nexp <= "0011";
            else
              opl_nexp <= "0000";
            end if;
            
          when others =>
            -- S2
            opl_bin <= not opl_sign;
            
            if OPL_MO = '0' then
              opl_nexp <= "1111";
            else
              opl_nexp <= "0000";
            end if;

            opl_len <= '1';

       end case;

      end if;

    end if;
  end process opl2_decode_p;

end architecture rtl;
   
