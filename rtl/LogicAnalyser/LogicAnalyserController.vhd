library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity LogicAnalyserController is
    generic(
         DATA_WIDTH  : natural := 8; --! width of a sample
         ADDR_WIDTH  : natural := 4; --! 2**ADDR_WIDTH = size if sample memory
         ASYNC_RESET : boolean := true
    );
    port(
        clk               : in  std_logic;
        rst               : in  std_logic;
        ce                : in  std_logic;

        --      host interface (UART or ....)
        data_dwn_valid    : in  std_logic;
        data_dwn          : in  std_logic_vector(7 downto 0);
        data_up_ready     : in  std_logic;
        data_up_valid     : out std_logic;
        data_up           : out std_logic_vector(7 downto 0);

        --      Trigger
        mask_curr         : out std_logic_vector(DATA_WIDTH-1 downto 0);
        value_curr        : out std_logic_vector(DATA_WIDTH-1 downto 0);
        mask_last         : out std_logic_vector(DATA_WIDTH-1 downto 0);
        value_last        : out std_logic_vector(DATA_WIDTH-1 downto 0);
        mask_edge         : out std_logic_vector(DATA_WIDTH-1 downto 0);

        --      Logic Analyser
        delay             : out std_logic_vector(ADDR_WIDTH-1 downto 0);
        trigger_active    : out std_logic;
        fire_trigger      : out std_logic;

        full              : in  std_logic;
        data              : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        data_request_next : out std_logic;
        data_valid        : in  std_logic;

        -- init
        finish            : in  std_logic
    );
end entity LogicAnalyserController;


architecture tab of LogicAnalyserController is

    constant HOST_WORD_SIZE : natural := 8;

    constant data_size      : natural := (DATA_WIDTH + HOST_WORD_SIZE - 1)/ HOST_WORD_SIZE;                                  -- Berechnung wie oft dass Mask, Value, Mask_last und Value_last eingelesen werden muss.
    constant addr_size      : natural := (ADDR_WIDTH + HOST_WORD_SIZE - 1)/ HOST_WORD_SIZE;                                  -- Berechnung wie oft, dass das Delay für das Memory eingelesen werden muss.
    constant DATA_WIDTH_slv : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(DATA_WIDTH, 32)); -- DATA_WIDTH_slv = Wert der Uebertragung des DATA_WIDTH
    constant ADDR_WIDTH_slv : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(ADDR_WIDTH, 32)); -- DATA_WIDTH_slv = Wert der Uebertragung des DATA_WIDTH

    ------------------------------------------------------------------Befehle um den LogicAnalyser zu bedienen-------------------------------------------------------------------------------------------------------------------------------------------------------------
    constant activate_trigger_command : std_logic_vector := "11111110";--FE
    constant fire_trigger_command     : std_logic_vector := "00000000";--00
    constant config_trigger_command   : std_logic_vector := "11110000";--f0
    constant logic_analyser_c         : std_logic_vector := "00001111";--0f
    constant select_curr_command      : std_logic_vector := "11110001";--f1
    constant set_mask_curr_command    : std_logic_vector := "11110011";--F3
    constant set_value_curr_command   : std_logic_vector := "11110111";--f7
    constant select_last_command      : std_logic_vector := "11111001";--F9
    constant set_mask_last_command    : std_logic_vector := "11111011";--fb
    constant set_value_last_command   : std_logic_vector := "11111111";--FF
    constant select_edge_command      : std_logic_vector := "11110101";--F5
    constant set_edge_mask_command    : std_logic_vector := "11110110";--F6
    constant set_delay_command        : std_logic_vector := "00011111";--1f
    constant get_sizes_command        : std_logic_vector := "10101010";--AA
    constant get_id_command           : std_logic_vector := "10111011";--BB

    constant I                        : std_logic_vector := "01001001";
    constant D                        : std_logic_vector := "01000100";
    constant B                        : std_logic_vector := "01000010";
    constant G                        : std_logic_vector := "01000111";
    --State machines
    type states_t      is(init, return_id, return_sizes, logic_analyser, set_delay,
                                         config_trigger, select_config_trigger_curr, select_config_trigger_last, select_config_trigger_edge,
                                         set_mask_curr, set_value_curr, set_mask_last, set_value_last, set_edge_mask, data_output);
    signal state       : states_t;

    type Output        is(init, Zwischenspeicher, shift, get_next_data);
    signal init_Output : Output;

    --Zähler
    signal data_size_s              : natural range 0 to data_size;
    signal addr_size_s              : natural range 0 to addr_size;

    signal mask_curr_s              : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal value_curr_s             : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal mask_last_s              : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal value_last_s             : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal mask_edge_s              : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal delay_s                  : std_logic_vector(ADDR_WIDTH-1 downto 0);

    signal counter                  : unsigned(ADDR_WIDTH-1 downto 0);
    signal import_ADDR              : std_logic;
    signal ende_ausgabe             : std_logic;
    signal theend                   : std_logic;
    signal la_data_temporary        : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal la_data_temporary_next   : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal sizes_temporary          : std_logic_vector(31 downto 0);
    signal send                     : std_logic_vector(7 downto 0);
    signal arst, srst               : std_logic;

    signal data_dwn_delayed         : std_logic_vector(7 downto 0);
    signal set_delay_next_byte      : std_logic;
    signal set_mask_curr_next_byte  : std_logic;
    signal set_value_curr_next_byte : std_logic;
    signal set_mask_last_next_byte  : std_logic;
    signal set_value_last_next_byte : std_logic;
    signal set_mask_edge_next_byte  : std_logic;

    signal data_up_from_la_data     : std_logic_vector(data_up'range);

    signal data_dwn_valid_reg       : std_logic;
    signal data_dwn_reg             : std_logic_vector(7 downto 0);

    signal get_id_active            : std_logic;
    signal get_sizes_active         : std_logic;
    signal activate_trigger_active  : std_logic;
    signal fire_trigger_active      : std_logic;
    signal config_trigger_active    : std_logic;
    signal logic_analyser_a         : std_logic;
    signal set_delay_active         : std_logic;
    signal select_curr_active       : std_logic;
    signal select_last_active       : std_logic;
    signal select_edge_active       : std_logic;
    signal set_value_curr_active    : std_logic;
    signal set_mask_curr_active     : std_logic;
    signal set_mask_last_active     : std_logic;
    signal set_value_last_active    : std_logic;
    signal set_edge_mask_active     : std_logic;

begin
    async_init: if ASYNC_RESET generate begin
        arst <= rst;
        srst <= '0';
    end generate async_init;
    sync_init: if not ASYNC_RESET generate begin
        arst <= '0';
        srst <= rst;
    end generate sync_init;


    data_dwn_registers: process(clk, arst)
        procedure reset_assignments is begin
            data_dwn_valid_reg <= '0';
            data_dwn_reg <= (others => '-');
        end procedure reset_assignments;
    begin
        if arst = '1' then
            reset_assignments;
        elsif rising_edge(clk) then
            if srst = '1' then
                reset_assignments;
            else
                if ce = '1' then
                    data_dwn_valid_reg <= data_dwn_valid;
                    data_dwn_reg       <= data_dwn;
                end if;
            end if;
        end if;
    end process;

    process(clk) begin
        if rising_edge(clk) then
            if ce = '1' then
                get_id_active <= '0';
                get_sizes_active <= '0';
                activate_trigger_active <= '0';
                fire_trigger_active <= '0';
                config_trigger_active <= '0';
                logic_analyser_a <= '0';
                set_delay_active <= '0';
                select_curr_active <= '0';
                select_last_active <= '0';
                select_edge_active <= '0';
                set_value_curr_active <= '0';
                set_mask_curr_active <= '0';
                set_mask_last_active <= '0';
                set_value_last_active <= '0';
                set_edge_mask_active <= '0';

                if data_dwn_valid = '1' then
                    if data_dwn = get_id_command then
                        get_id_active <= '1';
                    end if;
                    if data_dwn = get_sizes_command then
                        get_sizes_active <= '1';
                    end if;
                    if data_dwn = activate_trigger_command then
                        activate_trigger_active <= '1';
                    end if;
                    if data_dwn = fire_trigger_command then
                        fire_trigger_active <= '1';
                    end if;
                    if data_dwn = config_trigger_command then
                        config_trigger_active <= '1';
                    end if;
                    if data_dwn = logic_analyser_c then
                        logic_analyser_a <= '1';
                    end if;
                    if data_dwn = set_delay_command then
                        set_delay_active <= '1';
                    end if;

                    if data_dwn = select_curr_command then
                        select_curr_active <= '1';
                    end if;
                    if data_dwn = select_last_command then
                        select_last_active <= '1';
                    end if;
                    if data_dwn = select_edge_command then
                        select_edge_active <= '1';
                    end if;

                    if data_dwn = set_mask_curr_command then
                        set_mask_curr_active <= '1';
                    end if;
                    if data_dwn = set_value_curr_command then
                        set_value_curr_active <= '1';
                    end if;

                    if data_dwn = set_mask_last_command then
                        set_mask_last_active <= '1';
                    end if;
                    if data_dwn = set_value_last_command then
                        set_value_last_active <= '1';
                    end if;

                    if data_dwn = set_edge_mask_command then
                        set_edge_mask_active <= '1';
                    end if;

                end if;
            end if;
        end if;
    end process;


    process (clk, arst)
        procedure reset_assignments is begin
            data_size_s              <= 0;
            addr_size_s              <= 0;
            state                    <= init;
            init_Output              <= init;

            data_dwn_delayed         <= (others => '-');

            data_up_valid            <= '0';
            data_up                  <= (others => '-');
            trigger_active           <= '0';
            fire_trigger             <= '0';
            data_request_next        <= '0';

            counter                  <= (others => '-');
            import_ADDR              <= '-';
            la_data_temporary        <= (others => '-');
            sizes_temporary          <= (others => '-');
            ende_ausgabe             <= '0';
            theend                   <= '0';
            set_delay_next_byte      <= '0';
            set_mask_curr_next_byte  <= '0';
            set_value_curr_next_byte <= '0';
            set_mask_last_next_byte  <= '0';
            set_value_last_next_byte <= '0';
            set_mask_edge_next_byte  <= '0';
        end procedure reset_assignments;
    begin
        if arst = '1' then
            reset_assignments;
        elsif rising_edge(clk) then
            if srst = '1' then
                reset_assignments;
            else
                if ce = '1' then
                    set_delay_next_byte         <= '0';
                    set_mask_curr_next_byte     <= '0';
                    set_value_curr_next_byte    <= '0';
                    set_mask_last_next_byte     <= '0';
                    set_value_last_next_byte    <= '0';
                    set_mask_edge_next_byte     <= '0';
                    data_dwn_delayed            <= data_dwn_reg;
                    data_up_valid <= '0';
                    case state is
                    when init =>
                        counter <= (others => '0');
                        if full = '1' then
                            data_request_next <= '1';
                            state <= data_output;
                            la_data_temporary <= (others => '-');
                            ende_ausgabe <= '0';
                            theend <= '0';
                        end if;

                        if get_id_active = '1' then
                                state <= return_id;
                        end if;

                        if get_sizes_active = '1' then
                            sizes_temporary <= (others => '0');
                            state <= return_sizes;
                            import_ADDR <= '0';
                        end if;

                        if activate_trigger_active = '1' then
                            trigger_active <= '1';
                        end if;

                        if fire_trigger_active = '1' then
                            fire_trigger <= '1';
                        end if;

                        if config_trigger_active = '1' then
                            state <= config_trigger;
                        end if;

                        if logic_analyser_a = '1' then
                            state <= logic_analyser;
                        end if;

                    when return_id =>

                        case init_Output is
                        when init =>
                            if data_up_ready = '1' then
                                init_Output <= Zwischenspeicher;
                                send <= I;
                                counter <= (others => '0');
                            end if;

                        when Zwischenspeicher =>
                            if data_up_ready = '1' then
                                data_up <= send;
                                data_up_valid <= '1';
                                counter <= counter + 1;
                                init_Output <= shift;
                            end if;
                         when shift =>
                            data_up_valid <= '0';
                            init_Output <= get_next_data;

                        when get_next_data =>

                           if counter = to_unsigned(1, counter'length) then
                                send <= D;
                                 init_Output <= Zwischenspeicher;
                           end if;
                           if counter = to_unsigned(2, counter'length) then
                                send <= B;
                                init_Output <= Zwischenspeicher;
                           end if;
                           if counter = to_unsigned(3, counter'length) then
                                send <= G;
                                init_Output <= Zwischenspeicher;
                           end if;
                           if counter = to_unsigned(4, counter'length) then
                                init_Output <= init;
                                state <= init;
                           end if;

                        end case;


                    when return_sizes =>

                        case init_Output is
                        when init =>
                            if data_up_ready = '1' then
                                sizes_temporary <= DATA_WIDTH_slv;
                                init_Output <= Zwischenspeicher;
                            end if;

                        when Zwischenspeicher =>
                            if data_up_ready = '1' then
                                data_up <= sizes_temporary(data_up'range);
                                data_up_valid <= '1';
                                sizes_temporary <= x"00" & sizes_temporary( sizes_temporary'left downto data_up'length);
                                counter <= counter + 1;
                                init_Output <= shift;
                            end if;

                        when shift =>
                            data_up_valid <= '0';

                            if data_up_ready = '0' then
                                init_Output <= Zwischenspeicher;
                            end if;

                            if counter = to_unsigned(4, counter'length) then
                                if import_ADDR = '0' then
                                    init_Output <= get_next_data;
                                end if;
                            end if;

                            if counter = to_unsigned(4, counter'length) then
                                if import_ADDR = '1' then
                                    init_Output <= init;
                                    state <= init;
                                end if;
                            end if;

                        when get_next_data =>
                            if data_up_ready = '1' then
                                counter <= (others => '0');
                                import_ADDR <= '1';
                                sizes_temporary <= ADDR_WIDTH_slv;
                                init_Output <= Zwischenspeicher;
                            end if;
                        end case;

                    when logic_analyser =>
                        addr_size_s <= 0;
                        if set_delay_active = '1' then
                            state <= set_delay;
                        end if;

                    when set_delay =>
                        if data_dwn_valid_reg = '1' then
                            if addr_size_s + 1 = addr_size  then
                                state <= init;
                            end if;

                            addr_size_s <= addr_size_s + 1;
                            set_delay_next_byte <= '1';
                        end if;

                    when config_trigger =>
                        if select_curr_active = '1' then
                            state <= select_config_trigger_curr;
                        end if;

                        if select_last_active = '1' then
                            state <= select_config_trigger_last;
                        end if;

                        if select_edge_active = '1' then
                            state <= select_config_trigger_edge;
                        end if;
                    when select_config_trigger_curr =>
                        data_size_s <= 0;

                        if set_mask_curr_active = '1' then
                            state <= set_mask_curr;
                        end if;

                        if set_value_curr_active = '1' then
                            state <= set_value_curr;
                        end if;
                    when set_mask_curr =>
                        if data_dwn_valid_reg = '1' then
                            data_size_s <= data_size_s + 1;
                            set_mask_curr_next_byte <= '1';

                            if data_size_s + 1 = data_size   then
                                state <= init;
                            end if;
                        end if;

                    when set_value_curr =>
                        if data_dwn_valid_reg = '1' then
                            data_size_s <= data_size_s + 1;
                            set_value_curr_next_byte <= '1';

                            if data_size_s + 1 = data_size then
                                state <= init;
                            end if;
                        end if;

                    when select_config_trigger_last =>
                        data_size_s <= 0;
                        if set_mask_last_active = '1' then
                            state <= set_mask_last;
                        end if;

                        if set_value_last_active = '1' then
                            state <= set_value_last;
                        end if;
                    when set_mask_last =>
                        if data_dwn_valid_reg = '1' then
                            data_size_s <= data_size_s + 1;
                            set_mask_last_next_byte  <= '1';

                            if data_size_s +1 = data_size then
                                state <= init;
                            end if;
                        end if;

                    when set_value_last =>
                        if data_dwn_valid_reg = '1' then
                            data_size_s <= data_size_s + 1;
                            set_value_last_next_byte <= '1';

                            if data_size_s + 1 = data_size then
                                state <= init;
                            end if;
                        end if;

                    when select_config_trigger_edge =>
                        data_size_s <= 0;
                        if set_edge_mask_active = '1' then
                            state <= set_edge_mask;
                        end if;
                    when set_edge_mask =>
                        if data_dwn_valid_reg = '1' then
                            data_size_s <= data_size_s + 1;
                            set_mask_edge_next_byte <= '1';

                            if data_size_s + 1 = data_size then
                                state <= init;
                            end if;
                        end if;


                    when data_output =>
                        if finish = '1' then
                            trigger_active <= '0';
                            fire_trigger <= '0';
                            ende_ausgabe <= '1';
                        end if;

                        if theend = '1' then
                            state <= init;
                            init_Output <= init;
                        end if;

                        case init_Output is
                        when init =>
                            if data_valid = '1' then
                                la_data_temporary <= data;
                                init_Output <= Zwischenspeicher;
                            end if;

                        when Zwischenspeicher =>
                            data_request_next <= '0';
                            if data_up_ready = '1' then
                                data_up_valid <= '1';
                                data_up <= data_up_from_la_data;
                                la_data_temporary <= la_data_temporary_next;

                                counter <= counter + 1;
                                init_Output <= shift;
                            end if;

                        when shift =>
                            data_up_valid <= '0';
                            if data_up_ready = '0' then
                                init_Output <= Zwischenspeicher;
                            end if;

                            if counter = data_size then
                                data_request_next <= '1';
                                init_Output <= get_next_data;
                            end if;

                        when get_next_data =>
                            if ende_ausgabe = '1' then
                                theend <= '1' ;
                            end if;

                            if data_valid = '1' then
                                counter <= (others => '0');
                                la_data_temporary <= data;
                                init_Output <= Zwischenspeicher;
                            end if;
                        end case;
                    end case ;
                end if;
            end if;
        end if;
    end process;

    set_delay_narrow: if ADDR_WIDTH <= HOST_WORD_SIZE generate begin
        process (clk) begin
            if rising_edge(clk) then
                if ce = '1' then
                    if set_delay_next_byte = '1' then
                        delay_s <= data_dwn_delayed(delay_s'range);
                    end if;
                end if;
            end if;
        end process;
    end generate set_delay_narrow;
    set_delay_wide: if ADDR_WIDTH > HOST_WORD_SIZE generate begin
        process (clk) begin
            if rising_edge(clk) then
                if ce = '1' then
                    if set_delay_next_byte = '1' then
                        delay_s <= delay_s(delay_s'left-HOST_WORD_SIZE downto 0) & data_dwn_delayed;
                    end if;
                end if;
            end if;
        end process;
    end generate set_delay_wide;

    prepare_from_narrow_data: if DATA_WIDTH <= HOST_WORD_SIZE generate begin
        process (la_data_temporary) begin
            data_up_from_la_data                        <= (others => '0');
            data_up_from_la_data(DATA_WIDTH-1 downto 0) <= la_data_temporary;
        end process;
        la_data_temporary_next <= (others => '-');
    end generate;

    prepare_from_wide_data: if DATA_WIDTH > HOST_WORD_SIZE generate begin
        data_up_from_la_data <= la_data_temporary(data_up'range);
        la_data_temporary_next <= x"00" & la_data_temporary(la_data_temporary'left downto data_up'length);
    end generate;

    set_trigger_narrow: if DATA_WIDTH <= HOST_WORD_SIZE generate begin
        process (clk) begin
            if rising_edge(clk) then
                if ce = '1' then
                    if set_mask_curr_next_byte = '1' then
                        mask_curr_s <= data_dwn_delayed(mask_curr_s'range);
                    end if;
                    if set_value_curr_next_byte = '1' then
                        value_curr_s <= data_dwn_delayed(value_curr_s'range);
                    end if;
                    if set_mask_last_next_byte = '1' then
                        mask_last_s <= data_dwn_delayed(mask_last_s'range);
                    end if;
                    if set_value_last_next_byte = '1' then
                        value_last_s <= data_dwn_delayed(value_last_s'range);
                    end if;
                    if set_mask_edge_next_byte = '1' then
                        mask_edge_s <= data_dwn_delayed(mask_edge_s'range);
                    end if;
                end if;
            end if;
        end process;
    end generate set_trigger_narrow;
    set_trigger_wide: if DATA_WIDTH > HOST_WORD_SIZE generate begin
        process (clk) begin
            if rising_edge(clk) then
                if ce = '1' then
                    if set_mask_curr_next_byte = '1' then
                        mask_curr_s <= mask_curr_s(mask_curr_s'left-HOST_WORD_SIZE downto 0) & data_dwn_delayed;
                    end if;
                    if set_value_curr_next_byte = '1' then
                        value_curr_s <= value_curr_s(value_curr_s'left-HOST_WORD_SIZE downto 0) & data_dwn_delayed;
                    end if;
                    if set_mask_last_next_byte = '1' then
                        mask_last_s <= mask_last_s(mask_last_s'left-HOST_WORD_SIZE downto 0) & data_dwn_delayed;
                    end if;
                    if set_value_last_next_byte = '1' then
                        value_last_s <= value_last_s(value_last_s'left-HOST_WORD_SIZE downto 0) & data_dwn_delayed;
                    end if;
                    if set_mask_edge_next_byte = '1' then
                        mask_edge_s <= mask_edge_s(mask_edge_s'left-HOST_WORD_SIZE downto 0) & data_dwn_delayed;
                    end if;
                end if;
            end if;
        end process;
    end generate set_trigger_wide;

    delay      <= delay_s;
    mask_curr  <= mask_curr_s;
    value_curr <= value_curr_s;
    mask_last  <= mask_last_s;
    value_last <= value_last_s;
    mask_edge  <= mask_edge_s;


end architecture tab;
