-------------------------------------------------------------------------------
-- Module: imc_sram_32x256 (VHDL)
-- Description: Top-level IMC-SRAM — dual-port SRAM + Boolean compute unit.
--              256 rows x 32-bit. Memory Mode + Compute Mode (2-cycle FSM).
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity imc_sram_32x256 is
    port (
        clk          : in  std_logic;
        mode         : in  std_logic;                        -- 0=Memory, 1=Compute
        we           : in  std_logic;                        -- Write enable (Memory)
        addr_a       : in  std_logic_vector(7 downto 0);
        addr_b       : in  std_logic_vector(7 downto 0);
        addr_wr      : in  std_logic_vector(7 downto 0);    -- Write-back addr (Compute)
        din          : in  std_logic_vector(31 downto 0);
        op_sel       : in  std_logic_vector(2 downto 0);
        dout         : out std_logic_vector(31 downto 0);
        zero_flag    : out std_logic;
        ones_count   : out std_logic_vector(5 downto 0);
        compute_done : out std_logic
    );
end entity imc_sram_32x256;

architecture rtl of imc_sram_32x256 is

    -- FSM states
    type state_t is (S_IDLE, S_READ, S_COMPUTE);
    signal state, next_state : state_t;

    -- SRAM port signals
    signal sram_we_a   : std_logic;
    signal sram_addr_a : std_logic_vector(7 downto 0);
    signal sram_din_a  : std_logic_vector(31 downto 0);
    signal sram_dout_a : std_logic_vector(31 downto 0);
    signal sram_we_b   : std_logic;
    signal sram_addr_b : std_logic_vector(7 downto 0);
    signal sram_din_b  : std_logic_vector(31 downto 0);
    signal sram_dout_b : std_logic_vector(31 downto 0);

    -- Compute signals
    signal compute_result : std_logic_vector(31 downto 0);
    signal operand_a_reg  : std_logic_vector(31 downto 0);
    signal operand_b_reg  : std_logic_vector(31 downto 0);
    signal op_sel_reg     : std_logic_vector(2 downto 0);
    signal addr_wr_reg    : std_logic_vector(7 downto 0);

begin

    -- SRAM instance
    u_sram : entity work.sram_dual_port
        port map (
            clk    => clk,
            we_a   => sram_we_a,   addr_a => sram_addr_a,
            din_a  => sram_din_a,  dout_a => sram_dout_a,
            we_b   => sram_we_b,   addr_b => sram_addr_b,
            din_b  => sram_din_b,  dout_b => sram_dout_b
        );

    -- Compute unit instance
    u_compute : entity work.imc_compute_unit
        port map (
            operand_a  => operand_a_reg,
            operand_b  => operand_b_reg,
            op_sel     => op_sel_reg,
            result     => compute_result,
            zero_flag  => zero_flag,
            ones_count => ones_count
        );

    -- FSM next state (combinational)
    process (state, mode)
    begin
        case state is
            when S_IDLE =>
                if mode = '1' then
                    next_state <= S_READ;
                else
                    next_state <= S_IDLE;
                end if;
            when S_READ =>
                next_state <= S_COMPUTE;
            when S_COMPUTE =>
                next_state <= S_IDLE;
            when others =>
                next_state <= S_IDLE;
        end case;
    end process;

    -- FSM register
    process (clk)
    begin
        if rising_edge(clk) then
            state <= next_state;
        end if;
    end process;

    -- Latch operands + control on READ
    process (clk)
    begin
        if rising_edge(clk) then
            if state = S_READ then
                operand_a_reg <= sram_dout_a;
                operand_b_reg <= sram_dout_b;
                op_sel_reg    <= op_sel;
                addr_wr_reg   <= addr_wr;
            end if;
        end if;
    end process;

    -- SRAM port mux (combinational)
    process (state, mode, we, addr_a, addr_b, din, addr_wr_reg, compute_result)
    begin
        sram_we_a   <= '0';
        sram_addr_a <= addr_a;
        sram_din_a  <= (others => '0');
        sram_we_b   <= '0';
        sram_addr_b <= addr_b;
        sram_din_b  <= (others => '0');

        case state is
            when S_IDLE =>
                if mode = '0' then
                    sram_we_a   <= we;
                    sram_addr_a <= addr_a;
                    sram_din_a  <= din;
                else
                    sram_addr_a <= addr_a;
                    sram_addr_b <= addr_b;
                end if;
            when S_READ =>
                sram_addr_a <= addr_a;
                sram_addr_b <= addr_b;
            when S_COMPUTE =>
                sram_we_a   <= '1';
                sram_addr_a <= addr_wr_reg;
                sram_din_a  <= compute_result;
            when others =>
                null;
        end case;
    end process;

    -- Output + compute_done
    process (clk)
    begin
        if rising_edge(clk) then
            compute_done <= '0';

            case state is
                when S_IDLE =>
                    if mode = '0' then
                        dout <= sram_dout_a;
                    end if;
                when S_COMPUTE =>
                    dout         <= compute_result;
                    compute_done <= '1';
                when others =>
                    null;
            end case;
        end if;
    end process;

end architecture rtl;
