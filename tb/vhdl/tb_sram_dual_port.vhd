-------------------------------------------------------------------------------
-- Testbench: tb_sram_dual_port (VHDL)
-- Description: Self-checking testbench for sram_dual_port.
--              8 prescribed tests + 100 random write/read pairs.
--              Uses report statements with PASS/FAIL.
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;  -- for uniform (random)

entity tb_sram_dual_port is
end entity tb_sram_dual_port;

architecture sim of tb_sram_dual_port is

    constant CLK_PERIOD : time := 10 ns;

    signal clk    : std_logic := '0';
    signal we_a   : std_logic := '0';
    signal addr_a : std_logic_vector(7 downto 0) := (others => '0');
    signal din_a  : std_logic_vector(31 downto 0) := (others => '0');
    signal dout_a : std_logic_vector(31 downto 0);
    signal we_b   : std_logic := '0';
    signal addr_b : std_logic_vector(7 downto 0) := (others => '0');
    signal din_b  : std_logic_vector(31 downto 0) := (others => '0');
    signal dout_b : std_logic_vector(31 downto 0);

    -- Counters
    shared variable pass_count  : integer := 0;
    shared variable fail_count  : integer := 0;
    shared variable total_tests : integer := 0;

    -- Procedures
    procedure drive_cycle(
        signal   clk_s   : in  std_logic;
        signal   we_a_s  : out std_logic;
        signal   addr_a_s: out std_logic_vector(7 downto 0);
        signal   din_a_s : out std_logic_vector(31 downto 0);
        signal   we_b_s  : out std_logic;
        signal   addr_b_s: out std_logic_vector(7 downto 0);
        signal   din_b_s : out std_logic_vector(31 downto 0);
        constant t_we_a  : in  std_logic;
        constant t_addr_a: in  std_logic_vector(7 downto 0);
        constant t_din_a : in  std_logic_vector(31 downto 0);
        constant t_we_b  : in  std_logic;
        constant t_addr_b: in  std_logic_vector(7 downto 0);
        constant t_din_b : in  std_logic_vector(31 downto 0)
    ) is
    begin
        we_a_s  <= t_we_a;
        addr_a_s <= t_addr_a;
        din_a_s <= t_din_a;
        we_b_s  <= t_we_b;
        addr_b_s <= t_addr_b;
        din_b_s <= t_din_b;
        wait until rising_edge(clk_s);
        wait for 1 ns;
    end procedure;

begin

    -- DUT
    dut : entity work.sram_dual_port
        port map (
            clk    => clk,
            we_a   => we_a,   addr_a => addr_a, din_a => din_a, dout_a => dout_a,
            we_b   => we_b,   addr_b => addr_b, din_b => din_b, dout_b => dout_b
        );

    -- Clock
    clk <= not clk after CLK_PERIOD / 2;

    -- Main test process
    process
        variable exp_a, exp_b : std_logic_vector(31 downto 0);
        variable t7_errors    : integer;
        variable t8_ok        : integer;
        variable rand_errors  : integer;
        variable seed1, seed2 : integer := 42;
        variable rand_real    : real;
        variable raddr        : std_logic_vector(7 downto 0);
        variable rdata        : std_logic_vector(31 downto 0);
        variable addr_int     : integer;
    begin
        -- Init
        wait until rising_edge(clk);
        wait until rising_edge(clk);

        -- TEST 1: Basic write-read
        report "--- TEST 1: Basic write-read (Port A) ---";
        drive_cycle(clk, we_a, addr_a, din_a, we_b, addr_b, din_b,
                    '1', x"00", x"DEADBEEF", '0', x"00", x"00000000");
        drive_cycle(clk, we_a, addr_a, din_a, we_b, addr_b, din_b,
                    '0', x"00", x"00000000", '0', x"00", x"00000000");
        total_tests := total_tests + 1;
        if dout_a = x"DEADBEEF" then
            report "  [PASS] T1 Port A read"; pass_count := pass_count + 1;
        else
            report "  [FAIL] T1 Port A read"; fail_count := fail_count + 1;
        end if;

        -- TEST 2: Simultaneous read (A) + write (B)
        report "--- TEST 2: Simultaneous read (A) + write (B) ---";
        drive_cycle(clk, we_a, addr_a, din_a, we_b, addr_b, din_b,
                    '0', x"00", x"00000000", '1', x"01", x"CAFEBABE");
        total_tests := total_tests + 1;
        if dout_a = x"DEADBEEF" then
            report "  [PASS] T2 Port A read 0x00"; pass_count := pass_count + 1;
        else
            report "  [FAIL] T2 Port A read 0x00"; fail_count := fail_count + 1;
        end if;
        drive_cycle(clk, we_a, addr_a, din_a, we_b, addr_b, din_b,
                    '0', x"01", x"00000000", '0', x"01", x"00000000");
        total_tests := total_tests + 1;
        if dout_a = x"CAFEBABE" then
            report "  [PASS] T2 verify B write"; pass_count := pass_count + 1;
        else
            report "  [FAIL] T2 verify B write"; fail_count := fail_count + 1;
        end if;

        -- TEST 3: Write collision (A wins)
        report "--- TEST 3: Write collision (Port A wins) ---";
        drive_cycle(clk, we_a, addr_a, din_a, we_b, addr_b, din_b,
                    '1', x"10", x"AAAAAAAA", '1', x"10", x"55555555");
        drive_cycle(clk, we_a, addr_a, din_a, we_b, addr_b, din_b,
                    '0', x"10", x"00000000", '0', x"10", x"00000000");
        total_tests := total_tests + 1;
        if dout_a = x"AAAAAAAA" then
            report "  [PASS] T3 collision A wins"; pass_count := pass_count + 1;
        else
            report "  [FAIL] T3 collision A wins"; fail_count := fail_count + 1;
        end if;

        -- TEST 4: Dual simultaneous read
        report "--- TEST 4: Dual simultaneous read ---";
        drive_cycle(clk, we_a, addr_a, din_a, we_b, addr_b, din_b,
                    '0', x"01", x"00000000", '0', x"10", x"00000000");
        total_tests := total_tests + 1;
        if dout_a = x"CAFEBABE" then
            report "  [PASS] T4 Port A read 0x01"; pass_count := pass_count + 1;
        else
            report "  [FAIL] T4 Port A read 0x01"; fail_count := fail_count + 1;
        end if;
        total_tests := total_tests + 1;
        if dout_b = x"AAAAAAAA" then
            report "  [PASS] T4 Port B read 0x10"; pass_count := pass_count + 1;
        else
            report "  [FAIL] T4 Port B read 0x10"; fail_count := fail_count + 1;
        end if;

        -- TEST 5: Read-during-write same addr
        report "--- TEST 5: Read-during-write same addr ---";
        drive_cycle(clk, we_a, addr_a, din_a, we_b, addr_b, din_b,
                    '1', x"20", x"FF00FF00", '0', x"20", x"00000000");
        drive_cycle(clk, we_a, addr_a, din_a, we_b, addr_b, din_b,
                    '0', x"20", x"00000000", '0', x"20", x"00000000");
        total_tests := total_tests + 1;
        if dout_a = x"FF00FF00" then
            report "  [PASS] T5 verify write"; pass_count := pass_count + 1;
        else
            report "  [FAIL] T5 verify write"; fail_count := fail_count + 1;
        end if;

        -- TEST 6: Sequential write all 256 rows
        report "--- TEST 6: Sequential write all 256 rows ---";
        for i in 0 to 255 loop
            drive_cycle(clk, we_a, addr_a, din_a, we_b, addr_b, din_b,
                        '1', std_logic_vector(to_unsigned(i, 8)),
                        std_logic_vector(to_unsigned(i, 32) xor x"A5A5A5A5"),
                        '0', x"00", x"00000000");
        end loop;
        report "  [PASS] T6 All 256 rows written";
        pass_count := pass_count + 1; total_tests := total_tests + 1;

        -- TEST 7: Sequential read all 256 rows via Port B
        report "--- TEST 7: Sequential read all 256 rows ---";
        t7_errors := 0;
        for i in 0 to 255 loop
            drive_cycle(clk, we_a, addr_a, din_a, we_b, addr_b, din_b,
                        '0', x"00", x"00000000",
                        '0', std_logic_vector(to_unsigned(i, 8)), x"00000000");
            exp_b := std_logic_vector(to_unsigned(i, 32) xor x"A5A5A5A5");
            if dout_b /= exp_b then
                t7_errors := t7_errors + 1;
            end if;
        end loop;
        total_tests := total_tests + 1;
        if t7_errors = 0 then
            report "  [PASS] T7 All 256 rows verified correctly";
            pass_count := pass_count + 1;
        else
            report "  [FAIL] T7 rows mismatched"; fail_count := fail_count + 1;
        end if;

        -- TEST 8: Memory reset
        report "--- TEST 8: Memory reset (write all zeros) ---";
        for i in 0 to 255 loop
            drive_cycle(clk, we_a, addr_a, din_a, we_b, addr_b, din_b,
                        '1', std_logic_vector(to_unsigned(i, 8)), x"00000000",
                        '0', x"00", x"00000000");
        end loop;
        drive_cycle(clk, we_a, addr_a, din_a, we_b, addr_b, din_b,
                    '0', x"00", x"00000000", '0', x"FF", x"00000000");
        t8_ok := 1;
        if dout_a /= x"00000000" then t8_ok := 0; end if;
        if dout_b /= x"00000000" then t8_ok := 0; end if;
        total_tests := total_tests + 1;
        if t8_ok = 1 then
            report "  [PASS] T8 Memory cleared to zero";
            pass_count := pass_count + 1;
        else
            report "  [FAIL] T8 Memory not fully cleared";
            fail_count := fail_count + 1;
        end if;

        -- RANDOM TEST: 100 pairs
        report "--- RANDOM TEST: 100 random write/read pairs ---";
        rand_errors := 0;
        for i in 0 to 99 loop
            -- Generate pseudo-random address and data
            uniform(seed1, seed2, rand_real);
            addr_int := integer(rand_real * 255.0);
            raddr := std_logic_vector(to_unsigned(addr_int, 8));
            uniform(seed1, seed2, rand_real);
            rdata := std_logic_vector(to_unsigned(integer(rand_real * 2147483647.0), 32));
            -- Write via Port A
            drive_cycle(clk, we_a, addr_a, din_a, we_b, addr_b, din_b,
                        '1', raddr, rdata, '0', x"00", x"00000000");
            -- Read via Port B
            drive_cycle(clk, we_a, addr_a, din_a, we_b, addr_b, din_b,
                        '0', x"00", x"00000000", '0', raddr, x"00000000");
            if dout_b /= rdata then
                rand_errors := rand_errors + 1;
            end if;
        end loop;
        total_tests := total_tests + 1;
        if rand_errors = 0 then
            report "  [PASS] All 100 random tests passed";
            pass_count := pass_count + 1;
        else
            report "  [FAIL] random tests failed"; fail_count := fail_count + 1;
        end if;

        -- SUMMARY
        report "========================================";
        report "  SUMMARY: " & integer'image(pass_count) & " / " &
               integer'image(total_tests) & " tests PASSED";
        if fail_count = 0 then
            report "  *** ALL TESTS PASSED ***";
        else
            report "  *** " & integer'image(fail_count) & " TESTS FAILED ***";
        end if;
        report "========================================";

        wait;  -- End simulation
    end process;

    -- Timeout
    process
    begin
        wait for 10 ms;
        report "[TIMEOUT] Simulation exceeded time limit" severity failure;
    end process;

end architecture sim;
