library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity JtagHub is
    generic(
        MFF_LENGTH        : natural := 3;
        TARGET_TECHNOLOGY : natural range 0 to 3 := 3 -- '0': "ipdbgtap"    1: xilinx spartan 3   2: LFE2;   3: xilinx 7series
    );
    port(
       clk                : in  std_logic;
       ce                 : in  std_logic;

       TMS                : in  std_logic := '0';
       TCK                : in  std_logic := '0';
       TDI                : in  std_logic := '1';
       TDO                : out std_logic;

       DATAOUT            : out std_logic_vector(7 downto 0);

       Enable_LA          : out std_logic;
       Enable_IOVIEW      : out std_logic;
       Enable_GDB         : out std_logic;

       DATAINREADY_LA     : out std_logic;
       DATAINREADY_IOVIEW : out std_logic;
       DATAINREADY_GDB    : out std_logic;
       DATAINVALID_LA     : in  std_logic;
       DATAINVALID_IOVIEW : in  std_logic;
       DATAINVALID_GDB    : in  std_logic;
       DATAIN_LA          : in  std_logic_vector(7 downto 0);
       DATAIN_IOVIEW      : in  std_logic_vector(7 downto 0);          
       DATAIN_GDB         : in  std_logic_vector(7 downto 0)
    );
end JtagHub;

architecture structure of JtagHub is
    component JtagCdc is
        generic(
            MFF_LENGTH : natural
        );
        port(
            clk                : in  std_logic;
            ce                 : in  std_logic;

            DATAOUT            : out std_logic_vector(7 downto 0);
            Enable_LA          : out std_logic;
            Enable_IOVIEW      : out std_logic;
            Enable_GDB         : out std_logic;

            DATAINREADY_LA     : out std_logic;
            DATAINREADY_IOVIEW : out std_logic;
            DATAINREADY_GDB    : out std_logic;
            DATAINVALID_LA     : in  std_logic;
            DATAINVALID_IOVIEW : in  std_logic;
            DATAINVALID_GDB    : in  std_logic;
            DATAIN_LA          : in  std_logic_vector (7 downto 0);
            DATAIN_IOVIEW      : in  std_logic_vector (7 downto 0);
            DATAIN_GDB         : in  std_logic_vector (7 downto 0);

            DRCLK              : in  std_logic;
            USER               : in  std_logic;
            UPDATE             : in  std_logic;
            CAPTURE            : in  std_logic;
            SHIFT              : in  std_logic;
            TDI                : in  std_logic;
            TDO                : out std_logic
        );
    end component JtagCdc;

    signal DRCLK        : std_logic;
    signal USER         : std_logic;
    signal UPDATE       : std_logic;
    signal CAPTURE      : std_logic;
    signal SHIFT        : std_logic;
    signal TDI_i        : std_logic;
    signal TDO1         : std_logic;

begin

    xilinx_7series: if TARGET_TECHNOLOGY = 3 generate
        component BSCAN is
            port(
                capture : out std_logic;
                DRCLK1  : out std_logic;
                RESET   : out std_logic;
                USER1   : out std_logic;
                SHIFT   : out std_logic;
                UPDATE  : out  std_logic;
                TCK     : out std_logic;
                TDI     : out std_logic;
                TMS     : out std_logic;
                TDO1    : in  std_logic
            );
        end component BSCAN;

    begin

        BSCAN_7Series_inst  :  component BSCAN
            port map(
                capture => capture,
                DRCLK1  => DRCLK,
                RESET   => open,
                USER1   => USER,
                SHIFT   => SHIFT,
                UPDATE  => UPDATE,
                TCK     => open,
                TDI     => TDI_i,
                TMS     => open,
                TDO1    => TDO1
            );
        TDO <= '0'; -- to decrease  number of warnings only
    end generate;

    Lattice_LFE2_12E: if TARGET_TECHNOLOGY = 2 generate -- Lattice LFE2
        signal UPDATE1        : std_logic;
        signal CAPTURE1       : std_logic;
        signal SHIFT1         : std_logic;
        signal wasInShiftDr1  : std_logic;
        signal wasInUpdate    : std_logic;
        signal SHIFT_lfe      : std_logic;
        signal UPDATE_lfe     : std_logic;
        signal JCE1           : std_logic;
        signal JCE1_lfe       : std_logic;

        component JtagcWrapper is
            port(
                JTDO1   : in  std_logic;
                JTDO2   : in  std_logic;
                JTDI    : out std_logic;
                JTCK    : out std_logic;
                JRTI1   : out std_logic;
                JRTI2   : out std_logic;
                JSHIFT  : out std_logic;
                JUPDATE : out std_logic;
                JRSTN   : out std_logic;
                JCE1    : out std_logic;
                JCE2    : out std_logic
            );
        end component JtagcWrapper;
    begin

        jtag : component JtagcWrapper
            port map(
                JTDO1   => TDO1,--
                JTDO2   => '0',--
                JTDI    => TDI_i,--
                JTCK    => DRCLK,--
                JRTI1   => open,--
                JRTI2   => open,--
                JSHIFT  => SHIFT_lfe,--
                JUPDATE => UPDATE_lfe,--
                JRSTN   => open,
                JCE1    => JCE1_lfe,
                JCE2    => open
            );
        process(DRCLK)begin
            if falling_edge(DRCLK) then
                UPDATE  <= UPDATE_lfe;
                SHIFT   <= SHIFT_lfe;
                JCE1    <= JCE1_lfe;
            end if;
        end process;

        CAPTURE <= CAPTURE1;
        CAPTURE1 <= JCE1 and (not SHIFT);
        SHIFT1 <= JCE1 and SHIFT;

        USER <= UPDATE1 or CAPTURE1 or SHIFT1;

        process(DRCLK)begin
            if falling_edge(DRCLK) then
                if SHIFT1 = '1' then
                    wasInShiftDr1 <= '1';
                elsif UPDATE_lfe = '1' then
                    wasInShiftDr1 <= '0';
                end if;
                if wasInShiftDr1 = '1' then
                    UPDATE1 <= UPDATE_lfe;
                else
                    UPDATE1 <= '0';
                end if;
            end if;
        end process;
      TDO <= '0'; -- to decrease  number of warnings only
    end generate;

    xilinx_spartan3: if TARGET_TECHNOLOGY = 1 generate -- spartan 3
        component BSCAN is
            port(
                capture : out std_logic;
                DRCLK1  : out std_logic;
                DRCLK2  : out std_logic;
                RESET   : out std_logic;
                USER1   : out std_logic;
                USER2   : out std_logic;
                SHIFT   : out std_logic;
                TDI     : out std_logic;
                Update  : out std_logic;
                TDO1    : in  std_logic;
                TDO2    : in  std_logic
            );
        end component BSCAN;
    begin
        bscan_inst : component BSCAN
            port map(
                capture => CAPTURE,
                DRCLK1  => DRCLK,
                DRCLK2  => open,
                RESET   => open,
                USER1   => USER,
                USER2   => open,
                SHIFT   => SHIFT,
                TDI     => TDI_i,
                Update  => UPDATE,
                TDO1    => TDO1,
                TDO2    => '0'
            );
        TDO <= '0'; -- to decrease  number of warnings only
    end generate;

    ipdbg_tap: if TARGET_TECHNOLOGY = 0 generate -- ipdbg-tap
        component TAP is
            port(
                Capture : out std_logic;
                Shift   : out std_logic;
                Update  : out std_logic;
                TDI_o   : out std_logic;
                TDO_i   : in  std_logic;
                SEL     : out std_logic;
                DRCK    : out std_logic;
                TDI     : in  std_logic;
                TDO     : out std_logic;
                TMS     : in  std_logic;
                TCK     : in  std_logic
            );
        end component TAP;
    begin
        TAP_l : component TAP
            port map(
                Capture => CAPTURE,
                Shift   => SHIFT,
                Update  => UPDATE,
                TDI_o   => TDI_i,
                TDO_i   => TDO1,
                SEL     => USER,
                DRCK    => DRCLK,

                TDI     => TDI,
                TDO     => TDO,
                TMS     => TMS,
                TCK     => TCK
            );
    end generate;


    CDC : component JtagCdc
        generic map(
            MFF_LENGTH => MFF_LENGTH
        )
        port map(
            clk                => clk,
            ce                 => ce,

            DATAOUT            => DATAOUT,
            Enable_LA          => Enable_LA,
            Enable_IOVIEW      => Enable_IOVIEW,
            Enable_GDB         => Enable_GDB,

            DATAINREADY_LA     => DATAINREADY_LA,
            DATAINREADY_IOVIEW => DATAINREADY_IOVIEW,
            DATAINREADY_GDB    => DATAINREADY_GDB,
            DATAINVALID_LA     => DATAINVALID_LA,
            DATAINVALID_IOVIEW => DATAINVALID_IOVIEW,
            DATAINVALID_GDB    => DATAINVALID_GDB,
            DATAIN_LA          => DATAIN_LA,
            DATAIN_IOVIEW      => DATAIN_IOVIEW,
            DATAIN_GDB         => DATAIN_GDB,

            DRCLK              => DRCLK,
            USER               => USER,
            UPDATE             => UPDATE,
            CAPTURE            => CAPTURE,
            SHIFT              => SHIFT,
            TDI                => TDI_i,
            TDO                => TDO1
        );

end architecture structure;
