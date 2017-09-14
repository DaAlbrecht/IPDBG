
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
--use work.lfsr_pkg.all;

--library ice40;


entity TopTestBplR3x is
    generic(
        MFF_LENGTH : natural := 3;
        DATA_WIDTH : natural := 8;        --! width of a sample
        ADDR_WIDTH : natural := 8
    );
    port(
        RefClk      : in  std_logic; -- 10MHz

--        --Sync1_In  : in  std_logic_vector(12 downto 0);
--        Sync1_In    : in  std_logic;
--        --Sync2_In  : in  std_logic_vector(12 downto 0);
--        Sync2_In    : in  std_logic;
--        --Sync1_Out : out std_logic_vector(12 downto 0);
--        Sync1_Out   : out std_logic;
--        --Sync2_Out : out std_logic_vector(12 downto 0);
--        Sync3_In : in std_logic
        Input_DeviceunderTest_IOVIEW     : in std_logic_vector(7 downto 0);
        Output_DeviceunderTest_IOVIEW    : out std_logic_vector(7 downto 0);

        TMS : in  std_logic;
        TCK : in  std_logic;
        TDI : in  std_logic;
        TDO : out std_logic

        --SyncPwr   : in std_logic
    );
end;

architecture rtl of TopTestBplR3x is

    component JtagHub is
        generic(
            MFF_LENGTH        : natural;
            TARGET_TECHNOLOGY : natural
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
            DATAIN_GDB         : in  std_logic_vector (7 downto 0)
        );
    end component JtagHub;
    component IoViewTop is
        port(
            clk            : in  std_logic;
            rst            : in  std_logic;
            ce             : in  std_logic;
            data_in_valid  : in  std_logic;
            data_in        : in  std_logic_vector(7 downto 0);
            data_out_ready : in  std_logic;
            data_out_valid : out std_logic;
            data_out       : out std_logic_vector(7 downto 0);
	        probe_inputs   : in  std_logic_vector;
	        probe_outputs  : out std_logic_vector
        );
    end component IoViewTop;
    component TAPExtPins is
        port(
            TDI : in  std_logic;
            TDO : out std_logic;
            TMS : in  std_logic;
            TCK : in  std_logic
        );
    end component TAPExtPins;

    signal DataOut                       : std_logic_vector(7 downto 0);

    signal Enable_IOVIEW                 : std_logic;
    signal DATAINREADY_IOVIEW            : std_logic;
    signal DATAINVALID_IOVIEW            : std_logic;
    signal DATAIN_IOVIEW                 : std_logic_vector(7 downto 0);

    component SB_DFF
        port(
            d : in  std_logic;
            c : in  std_logic;
            q : out std_logic
        );
    end component;
    signal rst_tap   : std_logic;
    signal rst_tap_n : std_logic;
    signal clk : std_logic;

begin

    clk <= RefClk;

    SB_DFF_inst: SB_DFF
    port map (
        Q => rst_tap_n,     -- Registered Output
        C => TCK,           -- Clock
        D => '1'            -- Data
    );
    rst_tap <= not rst_tap_n;

    JtagExtPins : component TAPExtPins
        port map(
            TDI => TDI,
            TDO => TDO,
            TMS => TMS,
            TCK => TCK
        );
    jtag : component JtagHub
        generic map(
            MFF_LENGTH => MFF_LENGTH,
            TARGET_TECHNOLOGY => 0 -- ipdbg-tap
        )
        port map(
            clk                => clk,
            ce                 => '1',
            DATAOUT            => DATAOUT,
            Enable_LA          => open,
            Enable_IOVIEW      => Enable_IOVIEW,
            Enable_GDB         => open,
            DATAINREADY_LA     => open,
            DATAINREADY_IOVIEW => DATAINREADY_IOVIEW,
            DATAINREADY_GDB    => open,
            DATAINVALID_LA     => '0',
            DATAINVALID_IOVIEW => DATAINVALID_IOVIEW,
            DATAINVALID_GDB    => '0',
            DATAIN_LA          => (others => '0'),
            DATAIN_IOVIEW      => DATAIN_IOVIEW,
            DATAIN_GDB         => (others => '0')
        );
    IO : component IoViewTop
        port map(
            clk            => clk,
            rst            => '0',
            ce             => '1',
            data_in_valid  => Enable_IOVIEW,
            data_in        => DATAOUT,
            data_out_ready => DATAINREADY_IOVIEW,
            data_out_valid => DATAINVALID_IOVIEW,
            data_out       => DATAIN_IOVIEW,
            probe_inputs   => INPUT_DeviceUnderTest_Ioview,
            probe_outputs  => OUTPUT_DeviceUnderTest_Ioview
        );

--end architecture structure;
end;
