--
-- https://github.com/Lougous/b68k-av
--
-- audio processing unit
--

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity apu is

  port (
    RSTn  : in    std_logic;
    CLK25 : in    std_logic;

    TOP_64 : in std_logic;
--    CLKDIV : in   std_logic_vector(2 downto 0);
--
--    -- local bus
--    LWE   : in std_logic;
--    LA    : in std_logic;
--    LD    : in std_logic_vector(7 downto 0);
--
--    -- flags
--    EMPTY : out std_logic;
--    HFULL : out std_logic;
    
    -- Audio IF
    -- OPL2
    OPL_RSTn : out std_logic;
    OPL_MO   : in  std_logic;
    OPL_SH   : in  std_logic;
    
    -- audio out (PWM)
    PWM_R_HI : out    std_logic;
    PWM_R_LO : out    std_logic;
    PWM_L_HI : out    std_logic;
    PWM_L_LO : out    std_logic
    );

end entity apu;

architecture rtl of apu is

  signal opl2_dat         : std_logic_vector(15 downto 0);
  signal opl2_top_50khz   : std_logic;

  signal opl2_latch : std_logic_vector(15 downto 0);
  
  signal pwm_hi : std_logic_vector(5 downto 0) := (others => '0');
  signal pwm_lo : std_logic_vector(5 downto 0) := (others => '0');
  
begin

  ------------------------------------------------------------------------------
  -- OPL2 decoder
  ------------------------------------------------------------------------------
  OPL_RSTn <= RSTn;

  opl2_decoder_i : entity work.opl2_decoder
    port map (
      RSTn    => RSTn,
      CLK25   => CLK25,

      -- OPL2
      OPL_MO => OPL_MO,
      OPL_SH => OPL_SH,
    
      -- audio out
      OPL_TOP_50kHz   => opl2_top_50khz,
      OPL_DAT         => opl2_dat
      );

  ------------------------------------------------------------------------------
  -- PWM
  ------------------------------------------------------------------------------
  process (CLK25) is
  begin
    if rising_edge(CLK25) then
      if unsigned(pwm_hi) = 0 then
        PWM_R_HI <= '0';
        PWM_L_HI <= '0';
      else
        PWM_R_HI <= '1';
        PWM_L_HI <= '1';
        
        pwm_hi <= std_logic_vector(unsigned(pwm_hi) - 1);
      end if;
      
      if unsigned(pwm_lo) = 0 then
        PWM_R_LO <= '0';
        PWM_L_LO <= '0';
      else
        PWM_R_LO <= '1';
        PWM_L_LO <= '1';
        
        pwm_lo <= std_logic_vector(unsigned(pwm_lo) - 1);
      end if;
      
      if opl2_top_50khz = '1' then
        opl2_latch <= opl2_dat;
      end if;

      if TOP_64 = '1' then
        pwm_hi <= opl2_latch(15 downto 10);
        pwm_lo <= opl2_latch(9 downto 4);
      end if;
        
    end if;
  end process;
  
end architecture rtl;
