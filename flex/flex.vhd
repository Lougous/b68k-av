library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity flex is

  port (

    RSTn  : in    std_logic;
    CLK25 : in    std_logic;

    -- local bus
    LWEn  : in    std_logic;
    LREn  : in    std_logic;
    LA0   : in    std_logic;
    LALEn : in    std_logic;
    LAD   : inout std_logic_vector(7 downto 0);
    IRQn  : inout std_logic;

    -- memory
    --                        MSEL2  MSEL1  MSEL0
    -- none                     0      0      0
    -- none                     1      1      1
    -- low bank, lower byte     1      0      0
    -- low bank, upper byte     0      1      0
    -- low bank, both bytes     1      1      0
    -- high bank, lower byte    0      1      1
    -- high bank, upper byte    1      0      1
    -- high bank, both bytes    0      0      1
    MAD   : inout std_logic_vector(15 downto 0);
    MA0   : out   std_logic;
    MALE  : out   std_logic;
    MSEL  : out   std_logic_vector(2 downto 0);
    MWEn  : out   std_logic;
    MOEn  : out   std_logic;
    
    -- video out
    PDAT  : out   std_logic_vector(7 downto 0);
    PCLK  : out   std_logic;
    BLANK : out   std_logic;
    VSYNC : out   std_logic;
    HSYNC : out   std_logic;

    -- OPL2
    OPL_RSTn : out std_logic;
    OPL_MO   : in  std_logic;
    OPL_SH   : in  std_logic;
    
    -- audio out
    PWM_R_HI : out    std_logic;
    PWM_R_LO : out    std_logic;
    PWM_L_HI : out    std_logic;
    PWM_L_LO : out    std_logic
    );

end entity flex;

architecture rtl of flex is

  signal LD_out : std_logic_vector(7 downto 0);
  
  signal adsel    : std_logic_vector(2 downto 0);
  signal MAD_out  : std_logic_vector(15 downto 0);
  signal MAD_oe   : std_logic;
  signal MOEn_msk : std_logic;
  signal MWEn_r   : std_logic;
  signal MWEn_rr  : std_logic;
  signal MSEL_r   : std_logic_vector(2 downto 0);

  signal m_phase_90deg : std_logic;

  -- video
  signal v_hcnt      : std_logic_vector(9 downto 0);
  signal v_even_line : std_logic;
  signal v_top_frame : std_logic;
  signal v_top_line  : std_logic;
  signal v_top_eo2l  : std_logic;
  signal v_top_gpu   : std_logic;
  signal v_rb_enable : std_logic;

  -- local bus
  signal WE_meta : std_logic;
  signal WE_safe : std_logic;
  signal WE_d    : std_logic;
  signal g_lwe   : std_logic;
  signal g_busy  : std_logic;
  signal a_lwe   : std_logic;
  signal l_ad    : std_logic_vector(16 downto 0);

  -- registers
  signal reg_int_en      : std_logic;
  signal reg_int_fl      : std_logic;
--  signal reg_bg_delay_x : std_logic_vector(2 downto 0);
--  signal reg_bg_en      : std_logic;
--  signal reg_bg_LUT     : std_logic_vector(1 downto 0);
  -- 0: low-res 256 colors
  -- 1: mixed low-res 128 colors / hi-res 16 colors with tile restrictions
  signal reg_rb_mode_low : std_logic;
  -- frame buffer (0: 20000h to 3FFFFh, 1: 60000h to 7FFFFh)
  signal reg_rb_buffer   : std_logic;
  -- base address
  signal reg_rb_base     : std_logic_vector(16 downto 0);
  -- 0: use colors 128-191 for hi-res pixels
  -- 1: use colors 192-255 for hi-res pixels
  signal reg_rb_lut_page : std_logic;
  -- VRAM access banking, 8x 64kiB
  signal reg_c_ad : std_logic_vector(2 downto 0);

  -- memory arbiter
  signal m_phase    : std_logic;
  signal m_r_rack   : std_logic;
  
  signal m_g_ack    : std_logic;
  signal m_g_rack   : std_logic;
  signal m_g_wack   : std_logic;
  signal m_g_access : std_logic;
  
  signal m_c_access : std_logic;

  -- cpu memory access
  signal c_lwe  : std_logic;
  signal c_ad   : std_logic_vector(18 downto 0);
  signal c_dt   : std_logic_vector(7 downto 0);
  signal c_w_dt : std_logic_vector(15 downto 0);
  
  -- gpu memory access
  signal g_ad       : std_logic_vector(18 downto 0);
  signal g_we       : std_logic;
  signal g_wm       : std_logic_vector(1 downto 0);
  signal g_re       : std_logic;
  signal g_w_dt     : std_logic_vector(15 downto 0);

  -- read back memory access
  signal rb_addr    : std_logic_vector(18 downto 0);
  signal rb_re      : std_logic;

  -- audio
  signal a_top_32  : std_logic;
  signal a_top_64  : std_logic;
  signal a_empty : std_logic;
  signal a_hfull : std_logic;
  
begin  -- architecture rtl

  ------------------------------------------------------------------------------
  -- local bus
  ------------------------------------------------------------------------------
  -- address latch
  latch_p: process (LALEn) is
  begin
    if rising_edge(LALEn) then
--    if falling_edge(LALEn) then
      l_ad(16 downto 9) <= l_ad(8 downto 1);
      l_ad(8 downto 1)  <= LAD;
    end if;
  end process latch_p;

  cdc_wen_p: process (CLK25, RSTn) is
  begin
    if RSTn = '0' then
      WE_meta <= '0';
      WE_safe <= '0';
    elsif rising_edge(CLK25) then
      WE_meta <= not LWEn;
    elsif falling_edge(CLK25) then
      WE_safe <= WE_meta;
    end if;
  end process cdc_wen_p;

  lb_p: process (CLK25, RSTn) is
    variable reg_ad : std_logic_vector(2 downto 0);
  begin
    if RSTn = '0' then
      reg_int_en <= '0';
      reg_int_fl <= '0';

--      reg_rb_mode_low <= '0';
--      reg_rb_buffer   <= '0';
--      reg_rb_base     <= (others => '0');
--      reg_rb_lut_page <= '0';

      reg_c_ad <= (others => '0');
      
      WE_d    <= '0';
      
      g_lwe <= '0';
      a_lwe <= '0';
      c_lwe <= '0';

      c_dt <= (others => '0');

      l_ad(0) <= '0';
      
    elsif rising_edge(CLK25) then
      -- IRQn generation
      if (v_top_frame = '1') and (reg_int_en = '1') then
        reg_int_fl <= '1';
      end if;
      
      -- WEn falling edge
      WE_d    <= WE_safe;

      g_lwe <= '0';
      a_lwe <= '0';

      if m_c_access = '1' then
        c_lwe <= '0';
      end if;

      if (WE_safe = '1') and (WE_d = '0') then

        c_dt <= LAD;
        l_ad(0) <= LA0;

        if l_ad(16 downto 15) = "00" then
          -- registers
          reg_ad := l_ad(2 downto 1) & LA0;
          
          if reg_ad = "000" then
            -- ctrl
            reg_int_en <= LAD(0);
            reg_int_fl <= reg_int_fl and not LAD(1);
          elsif reg_ad = "001" then
            -- plan setup
--            reg_rb_base(16) <= LAD(0);
--            reg_rb_mode_low <= LAD(1);
--            reg_rb_buffer   <= LAD(2);
--            reg_rb_lut_page <= LAD(3);

            -- VRAM page
            reg_c_ad <= LAD(6 downto 4);
          elsif reg_ad = "010" then
            -- plan address LSB
--            reg_rb_base(7 downto 0) <= LAD;
          elsif reg_ad = "011" then
            -- plan address MSB
--            reg_rb_base(15 downto 8) <= LAD;
          elsif reg_ad = "100" or reg_ad = "101" then
            -- GPU registers
            g_lwe <= '1';          
          else
            -- APU registers
            a_lwe <= '1';          
          end if;
        else
          -- write access to VRAM
          c_lwe <= '1';
        end if;
        
      end if;

    end if;
  end process lb_p;

  c_ad <= reg_c_ad & l_ad(15 downto 1) & l_ad(0);

  -- data read
  LD_out <= g_busy & reg_c_ad & a_hfull & "0" & reg_int_fl & reg_int_en;

  
  LAD <= LD_out when LREn = '0' else (others => 'Z');

  IRQn <= '0' when reg_int_fl = '1' else 'Z';

  
  ------------------------------------------------------------------------------
  -- graphic processor
  ------------------------------------------------------------------------------
  gpu_i : entity work.gpu
    port map (
      RSTn  => RSTn,
      CLK25 => CLK25,

      -- local bus
      LWE  => g_lwe,
      LA   => l_ad(0),
      LD   => c_dt,
      BUSY => g_busy,

      -- 
      RB_BUFFER   => reg_rb_buffer,
      RB_BASE     => reg_rb_base,
      RB_LOWRES   => reg_rb_mode_low,
      RB_LUT_PAGE => reg_rb_lut_page,

      --
      VS => v_top_gpu,
      
      -- memory
      WE    => g_we,
      WM    => g_wm,
      RE    => g_re,
      AD    => g_ad,
      ACK   => m_g_ack,  --m_g_access,
      WDT   => g_w_dt,
      WDACK => m_g_wack,
      RDT   => MAD,
      RDACK => m_g_rack
      );

  
  ------------------------------------------------------------------------------
  -- video timing generator
  ------------------------------------------------------------------------------
  vtb_i : entity work.vtb
    port map (
      RSTn  => RSTn,
      CLK25 => CLK25,

      -- sync
      HSYNC     => HSYNC,
      VSYNC     => VSYNC,
      BLANK     => BLANK,
      EVEN_LINE => v_even_line,
      RB_ENABLE => v_rb_enable,
      TOP_FRAME => v_top_frame,
      TOP_LINE  => v_top_line,
      TOP_EO2L  => v_top_eo2l,
      TOP_GPU   => v_top_gpu,
      HCNT      => v_hcnt
      );

  
  ------------------------------------------------------------------------------
  -- video read back
  ------------------------------------------------------------------------------
  rb_i : entity work.rb
    port map (
      RSTn  => RSTn,
      CLK25 => CLK25,

      -- registers
      REG_BUFFER   => reg_rb_buffer,
      REG_BASE     => reg_rb_base,
      REG_LOWRES   => reg_rb_mode_low,
      REG_LUT_PAGE => reg_rb_lut_page,

      -- video timing
      TOP_FRAME => v_top_frame,
      TOP_LINE  => v_top_line,
      TOP_EO2L  => v_top_eo2l,
      EVEN_LINE => v_even_line,
      RB_ENABLE => v_rb_enable,
      HCNT      => v_hcnt,
    
      -- memory
      AD    => rb_addr,
      RE    => rb_re,
      RDT   => MAD,
      RACK  => m_r_rack,

      -- pixels out
      PCLK => PCLK,
      PDAT => PDAT
      );

  
  ------------------------------------------------------------------------------
  -- RAM access sequencer
  ------------------------------------------------------------------------------
  MAD <= MAD_out when MAD_oe = '1' else (others => 'Z');

--  m_c_wack <= '1' when v_hcnt(2 downto 0) = "000" and c_lwe = '1' else '0';

  -- address/data bus multiplexer
  adsel(2) <= '1' when v_hcnt(0) = '0' and m_c_access = '1' else '0';
           
  adsel(1 downto 0) <=
    "10" when v_hcnt(0) = '0' and m_g_access = '1' else
    "01" when v_hcnt(0) = '1' and rb_re = '1' else
    "00" when v_hcnt(0) = '1' and rb_re = '0' and c_lwe = '1' else
    "11";

  c_w_dt <= c_dt & c_dt;
  
  mux5_i : entity work.mux5
    generic map (
      WIDTH => 16
      )
    port map (
      CLK   => CLK25,
      SEL   => adsel,

      DA => c_ad(16 downto 1),
      DB => rb_addr(16 downto 1),
      DC => g_w_dt(15 downto 0),
      DD => g_ad(16 downto 1),
      DE => c_w_dt,

      Q => MAD_out
      );
  
  
  ramc_p: process (CLK25, RSTn) is
  begin
    if RSTn = '0' then
      MA0      <= '0';
      MWEn_r   <= '1';
      MSEL_r   <= (others => '0');

      m_phase  <= '1';
      
      m_r_rack   <= '0';
      
      m_g_ack    <= '0';
      m_g_rack   <= '0';
      m_g_wack   <= '0';
      m_g_access <= '0';

      m_c_access <= '0';

    elsif rising_edge(CLK25) then

      m_g_ack  <= '0';
      m_g_rack <= '0';
      m_g_wack <= '0';
      m_r_rack <= '0';

      m_phase <= not v_hcnt(0);

      if m_phase = '1' then
        -- first access part: address phase
        MSEL_r   <= (others => '0');
        MWEn_r <= '1';
        
        if rb_re = '1' then
          -- priority #1: read back
          -- read access only; 16-bits
          MA0  <= rb_addr(17);
          MSEL_r <= (not rb_addr(18)) &
                  (not rb_addr(18)) &
                  rb_addr(18);
        elsif c_lwe = '1' then
          -- priority #2: CPU
          -- write access only; 8-bits
          m_c_access <= '1';

          MA0    <= c_ad(17);
          MSEL_r   <= (not (c_ad(0) xor c_ad(18))) &
                    (c_ad(0) xor c_ad(18)) &
                    c_ad(18);
          MWEn_r <= '0';
        elsif g_re = '1' then
          -- priority #3a: GPU read
          -- 16-bits
          m_g_access <= '1';
          m_g_ack    <= '1';

          MA0  <= g_ad(17);
          MSEL_r <= (not g_ad(18)) &
                  (not g_ad(18)) &
                  g_ad(18);
           
        elsif g_we = '1' then
          -- priority #3b: GPU write
          -- 8-bits or 16-bits
          m_g_access <= '1';
          m_g_ack    <= '1';

          MA0    <= g_ad(17);
          MSEL_r <= (not g_ad(18)) &
                    (not g_ad(18)) &
                    g_ad(18);
          MWEn_r <= '0';
        end if;

      else
        -- second access part: data phase
        if m_g_access = '1' then
          if g_we = '1' then
            m_g_wack <= '1';
          else
            m_g_rack <= '1';
          end if;
        elsif m_c_access = '1' then
        elsif rb_re = '1' then
          m_r_rack   <= '1';
        end if;
        
        m_g_access <= '0';
        m_c_access <= '0';
          
        MWEn_r <= '1';
      end if;
      

    end if;
  end process ramc_p;

  MAD_oe <= not (MWEn_rr) or                -- data (write) phase
            (m_phase_90deg and (not m_phase))  -- address phase
            ;
--            after 2 ns;
  
  MALE <= m_phase_90deg and (not m_phase);
  MOEn <= MOEn_msk or m_phase_90deg;
  
  -- delay by half cycle MALE
  male_p: process (CLK25) is
  begin
    if falling_edge(CLK25) then
      m_phase_90deg <= m_phase;

      MWEn          <= MWEn_r;


      MWEn_rr       <= MWEn_r;
      MOEn_msk      <= m_phase or not (rb_re or (m_g_access and g_re));
--      MOEn_msk      <= m_phase or not (rb_re or (m_g_access and not m_g_wack));

      if m_phase = '0' then
      if m_g_access = '1' and g_we = '1' then
        MSEL <= (g_wm(0) xor MSEL_r(0)) & (g_wm(1) xor MSEL_r(0)) & MSEL_r(0);
      else
        MSEL <= MSEL_r;
      end if;
      end if;
      
    end if;
  end process male_p;
  
  
  ------------------------------------------------------------------------------
  -- audio processing unit
  ------------------------------------------------------------------------------
  top_64_p: process (RSTn, CLK25) is
  begin
    if RSTn = '0' then
      a_top_32 <= '0';
      a_top_64 <= '0';
      
    elsif rising_edge(CLK25) then
      if v_hcnt(4 downto 0) = "00000" then
        a_top_32 <= not a_top_32;
        a_top_64 <= a_top_32;
      else
        a_top_64 <= '0';
      end if;
    end if;
  end process top_64_p;

  apu_i : entity work.apu
     port map (
       RSTn   => RSTn,
       CLK25  => CLK25,
       TOP_64 => a_top_64,

  --     CLKDIV => v_hcnt(2 downto 0),

  --     -- LOCAL BUS
  --     LWE => a_lwe,
  --     LA  => LA0,
  --     LD  => c_dt,

  --     EMPTY => a_empty,
  --     HFULL => a_hfull,
      
  --     -- AUDIO IF
       -- OPL2
       OPL_RSTN => OPL_RSTn,
       OPL_MO   => OPL_MO,
       OPL_SH   => OPL_SH,
    
       -- audio out (PWM)
       PWM_R_HI => PWM_R_HI,
       PWM_R_LO => PWM_R_LO,
       PWM_L_HI => PWM_L_HI,
       PWM_L_LO => PWM_L_LO
       );

  a_empty <= a_lwe;
  a_hfull <= '0';

end architecture rtl;
