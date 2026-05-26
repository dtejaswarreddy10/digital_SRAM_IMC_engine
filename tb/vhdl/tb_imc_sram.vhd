-------------------------------------------------------------------------------
-- Testbench: tb_imc_sram (VHDL)
-- Description: Self-checking testbench for imc_sram_32x256 module.
--              Tests 1-8 (Memory Mode), Tests 9-16 (Compute Mode),
--              100 random compute ops, throughput benchmark.
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

entity tb_imc_sram is
end entity tb_imc_sram;

architecture sim of tb_imc_sram is

    constant CLK_PERIOD : time := 10 ns;

    signal clk          : std_logic := '0';
    signal mode         : std_logic := '0';
    signal we           : std_logic := '0';
    signal addr_a       : std_logic_vector(7 downto 0) := (others => '0');
    signal addr_b       : std_logic_vector(7 downto 0) := (others => '0');
    signal addr_wr      : std_logic_vector(7 downto 0) := (others => '0');
    signal din          : std_logic_vector(31 downto 0) := (others => '0');
    signal op_sel       : std_logic_vector(2 downto 0) := (others => '0');
    signal dout         : std_logic_vector(31 downto 0);
    signal zero_flag    : std_logic;
    signal ones_count   : std_logic_vector(5 downto 0);
    signal compute_done : std_logic;

    shared variable pass_count  : integer := 0;
    shared variable fail_count  : integer := 0;
    shared variable total_tests : integer := 0;

    -- ---------------------------------------------------------------
    -- Procedures
    -- ---------------------------------------------------------------

    procedure mem_write_proc(
        signal clk_s    : in  std_logic;
        signal mode_s   : out std_logic;
        signal we_s     : out std_logic;
        signal addr_a_s : out std_logic_vector(7 downto 0);
        signal addr_b_s : out std_logic_vector(7 downto 0);
        signal addr_wr_s: out std_logic_vector(7 downto 0);
        signal din_s    : out std_logic_vector(31 downto 0);
        signal op_sel_s : out std_logic_vector(2 downto 0);
        constant address : in std_logic_vector(7 downto 0);
        constant data    : in std_logic_vector(31 downto 0)
    ) is
    begin
        mode_s   <= '0';
        we_s     <= '1';
        addr_a_s <= address;
        din_s    <= data;
        addr_b_s <= (others => '0');
        addr_wr_s <= (others => '0');
        op_sel_s <= (others => '0');
        wait until rising_edge(clk_s);
        wait for 1 ns;
        we_s <= '0';
    end procedure;

    procedure mem_read_proc(
        signal clk_s    : in  std_logic;
        signal mode_s   : out std_logic;
        signal we_s     : out std_logic;
        signal addr_a_s : out std_logic_vector(7 downto 0);
        signal addr_b_s : out std_logic_vector(7 downto 0);
        signal addr_wr_s: out std_logic_vector(7 downto 0);
        signal din_s    : out std_logic_vector(31 downto 0);
        signal op_sel_s : out std_logic_vector(2 downto 0);
        signal dout_s   : in  std_logic_vector(31 downto 0);
        constant address : in std_logic_vector(7 downto 0);
        variable data_out: out std_logic_vector(31 downto 0)
    ) is
    begin
        mode_s   <= '0';
        we_s     <= '0';
        addr_a_s <= address;
        din_s    <= (others => '0');
        addr_b_s <= (others => '0');
        addr_wr_s <= (others => '0');
        op_sel_s <= (others => '0');
        wait until rising_edge(clk_s);
        wait for 1 ns;
        wait until rising_edge(clk_s);
        wait for 1 ns;
        data_out := dout_s;
    end procedure;

    procedure compute_op_proc(
        signal clk_s    : in  std_logic;
        signal mode_s   : out std_logic;
        signal we_s     : out std_logic;
        signal addr_a_s : out std_logic_vector(7 downto 0);
        signal addr_b_s : out std_logic_vector(7 downto 0);
        signal addr_wr_s: out std_logic_vector(7 downto 0);
        signal din_s    : out std_logic_vector(31 downto 0);
        signal op_sel_s : out std_logic_vector(2 downto 0);
        constant a_addr  : in std_logic_vector(7 downto 0);
        constant b_addr  : in std_logic_vector(7 downto 0);
        constant wr_addr : in std_logic_vector(7 downto 0);
        constant op      : in std_logic_vector(2 downto 0)
    ) is
    begin
        mode_s   <= '1';
        we_s     <= '0';
        addr_a_s <= a_addr;
        addr_b_s <= b_addr;
        addr_wr_s <= wr_addr;
        op_sel_s <= op;
        din_s    <= (others => '0');
        wait until rising_edge(clk_s); wait for 1 ns;  -- IDLE -> READ
        wait until rising_edge(clk_s); wait for 1 ns;  -- READ -> COMPUTE
        wait until rising_edge(clk_s); wait for 1 ns;  -- COMPUTE -> done
        mode_s <= '0';
        wait until rising_edge(clk_s); wait for 1 ns;  -- back to IDLE
    end procedure;

    -- Golden model functions
    function golden_compute(a : std_logic_vector(31 downto 0);
                            b : std_logic_vector(31 downto 0);
                            op : std_logic_vector(2 downto 0))
        return std_logic_vector is
    begin
        case op is
            when "000"  => return a and b;
            when "001"  => return a or b;
            when "010"  => return a xor b;
            when "011"  => return not (a or b);
            when "100"  => return not (a and b);
            when "101"  => return not (a xor b);
            when "110"  => return not a;
            when "111"  => return a;
            when others => return (others => '0');
        end case;
    end function;

    function golden_popcount(val : std_logic_vector(31 downto 0))
        return integer is
        variable cnt : integer := 0;
    begin
        cnt := 0;
        for k in 0 to 31 loop
            if val(k) = '1' then
                cnt := cnt + 1;
            end if;
        end loop;
        return cnt;
    end function;

begin

    -- DUT
    dut : entity work.imc_sram_32x256
        port map (
            clk          => clk,
            mode         => mode,
            we           => we,
            addr_a       => addr_a,
            addr_b       => addr_b,
            addr_wr      => addr_wr,
            din          => din,
            op_sel       => op_sel,
            dout         => dout,
            zero_flag    => zero_flag,
            ones_count   => ones_count,
            compute_done => compute_done
        );

    -- Clock
    clk <= not clk after CLK_PERIOD / 2;

    -- ---------------------------------------------------------------
    -- Main test process
    -- ---------------------------------------------------------------
    process
        variable rd_data       : std_logic_vector(31 downto 0);
        variable exp_data      : std_logic_vector(31 downto 0);
        variable t7_errors     : integer;
        variable t8_ok         : integer;
        variable t16_errors    : integer;
        variable rand_errors   : integer;
        variable seed1, seed2  : integer := 42;
        variable rand_real     : real;
        variable rand_a_v      : std_logic_vector(31 downto 0);
        variable rand_b_v      : std_logic_vector(31 downto 0);
        variable rand_op_v     : std_logic_vector(2 downto 0);
        variable golden_r      : std_logic_vector(31 downto 0);
        variable golden_pc_v   : integer;
        variable exp_xnor      : std_logic_vector(31 downto 0);
        variable exp_pc_int    : integer;
        variable imc_start     : time;
        variable imc_finish    : time;
        variable conv_start    : time;
        variable conv_finish   : time;
        variable imc_cyc       : integer;
        variable conv_cyc      : integer;
        variable val_a         : std_logic_vector(31 downto 0);
        variable val_b         : std_logic_vector(31 downto 0);
        variable conv_result   : std_logic_vector(31 downto 0);
        variable addr_int      : integer;
    begin
        wait until rising_edge(clk);
        wait until rising_edge(clk);

        -- =============================================================
        --  MEMORY MODE TESTS (Tests 1-8)
        -- =============================================================

        -- TEST 1: Basic write-read
        report "--- TEST 1: Basic write-read ---";
        mem_write_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                       x"00", x"DEADBEEF");
        mem_read_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel, dout,
                      x"00", rd_data);
        total_tests := total_tests + 1;
        if rd_data = x"DEADBEEF" then
            report "  [PASS] T1 read addr 0x00";
            pass_count := pass_count + 1;
        else
            report "  [FAIL] T1 read addr 0x00";
            fail_count := fail_count + 1;
        end if;

        -- TEST 2: Write addr 0x01, read addr 0x00
        report "--- TEST 2: Write addr 0x01, read addr 0x00 ---";
        mem_write_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                       x"01", x"CAFEBABE");
        mem_read_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel, dout,
                      x"00", rd_data);
        total_tests := total_tests + 1;
        if rd_data = x"DEADBEEF" then
            report "  [PASS] T2 read addr 0x00";
            pass_count := pass_count + 1;
        else
            report "  [FAIL] T2 read addr 0x00";
            fail_count := fail_count + 1;
        end if;
        mem_read_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel, dout,
                      x"01", rd_data);
        total_tests := total_tests + 1;
        if rd_data = x"CAFEBABE" then
            report "  [PASS] T2 read addr 0x01";
            pass_count := pass_count + 1;
        else
            report "  [FAIL] T2 read addr 0x01";
            fail_count := fail_count + 1;
        end if;

        -- TEST 3: Overwrite test
        report "--- TEST 3: Overwrite test ---";
        mem_write_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                       x"10", x"AAAAAAAA");
        mem_write_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                       x"10", x"55555555");
        mem_read_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel, dout,
                      x"10", rd_data);
        total_tests := total_tests + 1;
        if rd_data = x"55555555" then
            report "  [PASS] T3 overwrite wins";
            pass_count := pass_count + 1;
        else
            report "  [FAIL] T3 overwrite wins";
            fail_count := fail_count + 1;
        end if;
        -- Restore for later tests
        mem_write_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                       x"10", x"AAAAAAAA");

        -- TEST 4: Read two addresses
        report "--- TEST 4: Read two addresses ---";
        mem_read_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel, dout,
                      x"01", rd_data);
        total_tests := total_tests + 1;
        if rd_data = x"CAFEBABE" then
            report "  [PASS] T4 read addr 0x01";
            pass_count := pass_count + 1;
        else
            report "  [FAIL] T4 read addr 0x01";
            fail_count := fail_count + 1;
        end if;
        mem_read_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel, dout,
                      x"10", rd_data);
        total_tests := total_tests + 1;
        if rd_data = x"AAAAAAAA" then
            report "  [PASS] T4 read addr 0x10";
            pass_count := pass_count + 1;
        else
            report "  [FAIL] T4 read addr 0x10";
            fail_count := fail_count + 1;
        end if;

        -- TEST 5: Write then read same addr
        report "--- TEST 5: Write then read same addr ---";
        mem_write_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                       x"20", x"FF00FF00");
        mem_read_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel, dout,
                      x"20", rd_data);
        total_tests := total_tests + 1;
        if rd_data = x"FF00FF00" then
            report "  [PASS] T5 read after write";
            pass_count := pass_count + 1;
        else
            report "  [FAIL] T5 read after write";
            fail_count := fail_count + 1;
        end if;

        -- TEST 6: Sequential write all 256 rows
        report "--- TEST 6: Sequential write all 256 rows ---";
        for i in 0 to 255 loop
            mem_write_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                           std_logic_vector(to_unsigned(i, 8)),
                           std_logic_vector(to_unsigned(i, 32) xor x"A5A5A5A5"));
        end loop;
        report "  [PASS] T6 All 256 rows written";
        pass_count := pass_count + 1;
        total_tests := total_tests + 1;

        -- TEST 7: Sequential read all 256 rows
        report "--- TEST 7: Sequential read all 256 rows ---";
        t7_errors := 0;
        for i in 0 to 255 loop
            mem_read_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel, dout,
                          std_logic_vector(to_unsigned(i, 8)), rd_data);
            exp_data := std_logic_vector(to_unsigned(i, 32) xor x"A5A5A5A5");
            if rd_data /= exp_data then
                t7_errors := t7_errors + 1;
            end if;
        end loop;
        total_tests := total_tests + 1;
        if t7_errors = 0 then
            report "  [PASS] T7 All 256 rows verified";
            pass_count := pass_count + 1;
        else
            report "  [FAIL] T7 rows mismatched";
            fail_count := fail_count + 1;
        end if;

        -- TEST 8: Memory reset
        report "--- TEST 8: Memory reset (all zeros) ---";
        for i in 0 to 255 loop
            mem_write_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                           std_logic_vector(to_unsigned(i, 8)), x"00000000");
        end loop;
        t8_ok := 1;
        mem_read_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel, dout,
                      x"00", rd_data);
        if rd_data /= x"00000000" then t8_ok := 0; end if;
        mem_read_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel, dout,
                      x"FF", rd_data);
        if rd_data /= x"00000000" then t8_ok := 0; end if;
        mem_read_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel, dout,
                      x"80", rd_data);
        if rd_data /= x"00000000" then t8_ok := 0; end if;
        total_tests := total_tests + 1;
        if t8_ok = 1 then
            report "  [PASS] T8 Memory cleared";
            pass_count := pass_count + 1;
        else
            report "  [FAIL] T8 Memory not fully cleared";
            fail_count := fail_count + 1;
        end if;

        -- =============================================================
        --  COMPUTE MODE TESTS (Tests 9-16)
        -- =============================================================

        -- TEST 9: AND complementary
        report "--- TEST 9: AND (0xAAAAAAAA & 0x55555555) ---";
        mem_write_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                       x"00", x"AAAAAAAA");
        mem_write_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                       x"01", x"55555555");
        compute_op_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                        x"00", x"01", x"F0", "000");
        total_tests := total_tests + 1;
        if dout = x"00000000" then
            report "  [PASS] T9 AND result";
            pass_count := pass_count + 1;
        else
            report "  [FAIL] T9 AND result";
            fail_count := fail_count + 1;
        end if;
        total_tests := total_tests + 1;
        if zero_flag = '1' then
            report "  [PASS] T9 zero_flag";
            pass_count := pass_count + 1;
        else
            report "  [FAIL] T9 zero_flag";
            fail_count := fail_count + 1;
        end if;

        -- TEST 10: OR fills all bits
        report "--- TEST 10: OR (0xAAAAAAAA | 0x55555555) ---";
        compute_op_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                        x"00", x"01", x"F1", "001");
        total_tests := total_tests + 1;
        if dout = x"FFFFFFFF" then
            report "  [PASS] T10 OR result";
            pass_count := pass_count + 1;
        else
            report "  [FAIL] T10 OR result";
            fail_count := fail_count + 1;
        end if;
        total_tests := total_tests + 1;
        if unsigned(ones_count) = to_unsigned(32, 6) then
            report "  [PASS] T10 ones_count=32";
            pass_count := pass_count + 1;
        else
            report "  [FAIL] T10 ones_count";
            fail_count := fail_count + 1;
        end if;

        -- TEST 11: XOR
        report "--- TEST 11: XOR (0xFF00FF00 ^ 0x0FF00FF0) ---";
        mem_write_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                       x"02", x"FF00FF00");
        mem_write_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                       x"03", x"0FF00FF0");
        compute_op_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                        x"02", x"03", x"F2", "010");
        total_tests := total_tests + 1;
        if dout = x"F0F0F0F0" then
            report "  [PASS] T11 XOR result";
            pass_count := pass_count + 1;
        else
            report "  [FAIL] T11 XOR result";
            fail_count := fail_count + 1;
        end if;
        total_tests := total_tests + 1;
        if unsigned(ones_count) = to_unsigned(16, 6) then
            report "  [PASS] T11 ones_count=16";
            pass_count := pass_count + 1;
        else
            report "  [FAIL] T11 ones_count";
            fail_count := fail_count + 1;
        end if;

        -- TEST 12: NAND all-ones
        report "--- TEST 12: NAND (0xFFFFFFFF ~& 0xFFFFFFFF) ---";
        mem_write_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                       x"04", x"FFFFFFFF");
        mem_write_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                       x"05", x"FFFFFFFF");
        compute_op_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                        x"04", x"05", x"F3", "100");
        total_tests := total_tests + 1;
        if dout = x"00000000" then
            report "  [PASS] T12 NAND result";
            pass_count := pass_count + 1;
        else
            report "  [FAIL] T12 NAND result";
            fail_count := fail_count + 1;
        end if;
        total_tests := total_tests + 1;
        if zero_flag = '1' then
            report "  [PASS] T12 zero_flag";
            pass_count := pass_count + 1;
        else
            report "  [FAIL] T12 zero_flag";
            fail_count := fail_count + 1;
        end if;

        -- TEST 13: XNOR identical
        report "--- TEST 13: XNOR (0x12345678 ~^ 0x12345678) ---";
        mem_write_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                       x"06", x"12345678");
        mem_write_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                       x"07", x"12345678");
        compute_op_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                        x"06", x"07", x"F4", "101");
        total_tests := total_tests + 1;
        if dout = x"FFFFFFFF" then
            report "  [PASS] T13 XNOR identical";
            pass_count := pass_count + 1;
        else
            report "  [FAIL] T13 XNOR identical";
            fail_count := fail_count + 1;
        end if;
        total_tests := total_tests + 1;
        if unsigned(ones_count) = to_unsigned(32, 6) then
            report "  [PASS] T13 ones_count=32";
            pass_count := pass_count + 1;
        else
            report "  [FAIL] T13 ones_count";
            fail_count := fail_count + 1;
        end if;

        -- TEST 14: XNOR non-equal (Hamming)
        report "--- TEST 14: XNOR (0x12345678 ~^ 0x87654321) ---";
        mem_write_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                       x"08", x"12345678");
        mem_write_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                       x"09", x"87654321");
        compute_op_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                        x"08", x"09", x"F5", "101");
        exp_xnor := not (x"12345678" xor x"87654321");
        exp_pc_int := golden_popcount(exp_xnor);
        total_tests := total_tests + 1;
        if dout = exp_xnor then
            report "  [PASS] T14 XNOR result";
            pass_count := pass_count + 1;
        else
            report "  [FAIL] T14 XNOR result";
            fail_count := fail_count + 1;
        end if;
        total_tests := total_tests + 1;
        if to_integer(unsigned(ones_count)) < 32 then
            report "  [PASS] T14 ones_count < 32 (non-equal)";
            pass_count := pass_count + 1;
        else
            report "  [FAIL] T14 ones_count should be < 32";
            fail_count := fail_count + 1;
        end if;
        total_tests := total_tests + 1;
        if to_integer(unsigned(ones_count)) = exp_pc_int then
            report "  [PASS] T14 popcount exact";
            pass_count := pass_count + 1;
        else
            report "  [FAIL] T14 popcount exact";
            fail_count := fail_count + 1;
        end if;

        -- TEST 15: NOT A
        report "--- TEST 15: NOT A (0xDEADBEEF) ---";
        mem_write_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                       x"0A", x"DEADBEEF");
        compute_op_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                        x"0A", x"00", x"F6", "110");
        total_tests := total_tests + 1;
        if dout = x"21524110" then
            report "  [PASS] T15 NOT A result";
            pass_count := pass_count + 1;
        else
            report "  [FAIL] T15 NOT A result";
            fail_count := fail_count + 1;
        end if;

        -- TEST 16: Bulk stress (128 AND pairs)
        report "--- TEST 16: Bulk stress (128 AND pairs) ---";
        for i in 0 to 255 loop
            mem_write_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                           std_logic_vector(to_unsigned(i, 8)),
                           std_logic_vector(to_unsigned(i, 32) xor x"DEADDEAD"));
        end loop;
        -- Compute AND: row[i] AND row[i+128] -> row[i] for i=0..127
        for i in 0 to 127 loop
            compute_op_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                            std_logic_vector(to_unsigned(i, 8)),
                            std_logic_vector(to_unsigned(i + 128, 8)),
                            std_logic_vector(to_unsigned(i, 8)),
                            "000");
        end loop;
        -- Verify
        t16_errors := 0;
        for i in 0 to 127 loop
            mem_read_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel, dout,
                          std_logic_vector(to_unsigned(i, 8)), rd_data);
            exp_data := (std_logic_vector(to_unsigned(i, 32) xor x"DEADDEAD")) and
                        (std_logic_vector(to_unsigned(i + 128, 32) xor x"DEADDEAD"));
            if rd_data /= exp_data then
                t16_errors := t16_errors + 1;
            end if;
        end loop;
        total_tests := total_tests + 1;
        if t16_errors = 0 then
            report "  [PASS] T16 All 128 AND pairs correct";
            pass_count := pass_count + 1;
        else
            report "  [FAIL] T16 AND pairs incorrect";
            fail_count := fail_count + 1;
        end if;

        -- =============================================================
        --  THROUGHPUT BENCHMARK
        -- =============================================================
        report "--- THROUGHPUT BENCHMARK: 128 AND ops ---";

        -- Prepare data
        for i in 0 to 255 loop
            uniform(seed1, seed2, rand_real);
            mem_write_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                           std_logic_vector(to_unsigned(i, 8)),
                           std_logic_vector(to_unsigned(integer(rand_real * 2147483647.0), 32)));
        end loop;

        -- IMC approach
        imc_start := now;
        for i in 0 to 127 loop
            compute_op_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                            std_logic_vector(to_unsigned(i, 8)),
                            std_logic_vector(to_unsigned(i + 128, 8)),
                            std_logic_vector(to_unsigned(i, 8)),
                            "000");
        end loop;
        imc_finish := now;
        imc_cyc := (imc_finish - imc_start) / CLK_PERIOD;
        report "  IMC: 128 ops in " & integer'image(imc_cyc) & " cycles";

        -- Conventional approach
        for i in 0 to 255 loop
            uniform(seed1, seed2, rand_real);
            mem_write_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                           std_logic_vector(to_unsigned(i, 8)),
                           std_logic_vector(to_unsigned(integer(rand_real * 2147483647.0), 32)));
        end loop;

        conv_start := now;
        for i in 0 to 127 loop
            mem_read_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel, dout,
                          std_logic_vector(to_unsigned(i, 8)), val_a);
            mem_read_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel, dout,
                          std_logic_vector(to_unsigned(i + 128, 8)), val_b);
            conv_result := val_a and val_b;
            mem_write_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                           std_logic_vector(to_unsigned(i, 8)), conv_result);
        end loop;
        conv_finish := now;
        conv_cyc := (conv_finish - conv_start) / CLK_PERIOD;
        report "  Conventional: 128 ops in " & integer'image(conv_cyc) & " cycles";
        report "  Speedup: conv/imc = " & integer'image(conv_cyc) & "/" & integer'image(imc_cyc);

        -- =============================================================
        --  100 RANDOM COMPUTE OPS
        -- =============================================================
        report "--- RANDOM COMPUTE: 100 ops vs golden model ---";
        rand_errors := 0;
        for i in 0 to 99 loop
            -- Random operands
            uniform(seed1, seed2, rand_real);
            rand_a_v := std_logic_vector(to_unsigned(integer(rand_real * 2147483647.0), 32));
            uniform(seed1, seed2, rand_real);
            rand_b_v := std_logic_vector(to_unsigned(integer(rand_real * 2147483647.0), 32));
            uniform(seed1, seed2, rand_real);
            rand_op_v := std_logic_vector(to_unsigned(integer(rand_real * 7.0), 3));

            mem_write_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                           x"E0", rand_a_v);
            mem_write_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                           x"E1", rand_b_v);
            compute_op_proc(clk, mode, we, addr_a, addr_b, addr_wr, din, op_sel,
                            x"E0", x"E1", x"E2", rand_op_v);

            golden_r    := golden_compute(rand_a_v, rand_b_v, rand_op_v);
            golden_pc_v := golden_popcount(golden_r);

            if dout /= golden_r or to_integer(unsigned(ones_count)) /= golden_pc_v then
                rand_errors := rand_errors + 1;
            end if;
        end loop;
        total_tests := total_tests + 1;
        if rand_errors = 0 then
            report "  [PASS] All 100 random compute ops verified";
            pass_count := pass_count + 1;
        else
            report "  [FAIL] random compute ops failed";
            fail_count := fail_count + 1;
        end if;

        -- =============================================================
        --  SUMMARY
        -- =============================================================
        report "========================================";
        report "  SUMMARY: " & integer'image(pass_count) & " / " &
               integer'image(total_tests) & " tests PASSED";
        if fail_count = 0 then
            report "  *** ALL TESTS PASSED ***";
        else
            report "  *** " & integer'image(fail_count) & " TESTS FAILED ***";
        end if;
        report "========================================";

        wait;
    end process;

    -- Timeout
    process
    begin
        wait for 500 ms;
        report "[TIMEOUT] Simulation exceeded time limit" severity failure;
    end process;

end architecture sim;
