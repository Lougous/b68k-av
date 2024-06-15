--
-- https://github.com/Lougous/b68k-av
--
-- 5:1 mux
--
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity mux5 is

  generic (
    WIDTH : integer
    );
  port (

    CLK   : in    std_logic;

    SEL : in std_logic_vector(2 downto 0);

    DA : in std_logic_vector(WIDTH-1 downto 0);
    DB : in std_logic_vector(WIDTH-1 downto 0);
    DC : in std_logic_vector(WIDTH-1 downto 0);
    DD : in std_logic_vector(WIDTH-1 downto 0);
    DE : in std_logic_vector(WIDTH-1 downto 0);

    Q : out std_logic_vector(WIDTH-1 downto 0)
    );

end entity mux5;

architecture rtl of mux5 is

  signal stage_ab : std_logic_vector(WIDTH-1 downto 0);
  signal stage_cd : std_logic_vector(WIDTH-1 downto 0);
  
begin  -- architecture rtl

  stage_ab <= DA when SEL(1 downto 0) = "00" else DB when SEL(1 downto 0) = "01" else (others => '0');
  stage_cd <= DC when SEL(1 downto 0) = "10" else DD when SEL(1 downto 0) = "11" else (others => '0');

  regout_p: process (CLK) is
  begin
    if rising_edge(CLK) then
      if SEL(2) = '1' then
        Q <= DE;
      else
        Q <= stage_ab or stage_cd;
      end if;
      
    end if;
  end process regout_p;

    
end architecture rtl;
