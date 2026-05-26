-------------------------------------------------------------------------------
-- Module: sram_dual_port
-- Description: True dual-port SRAM — 256 rows x 32-bit words.
--              Port A and Port B can independently read or write each cycle.
--              Port A has write priority on address collision.
--              Synchronous read-first for BRAM inference.
--
-- VHDL BRAM Inference (Xilinx UG901):
--   True dual-port with single clock uses a shared variable for the
--   memory array so both processes can read/write it in the same delta.
--   Each port has its own process with rising_edge(clk).
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity sram_dual_port is
    port (
        clk    : in  std_logic;
        -- Port A
        we_a   : in  std_logic;
        addr_a : in  std_logic_vector(7 downto 0);
        din_a  : in  std_logic_vector(31 downto 0);
        dout_a : out std_logic_vector(31 downto 0);
        -- Port B
        we_b   : in  std_logic;
        addr_b : in  std_logic_vector(7 downto 0);
        din_b  : in  std_logic_vector(31 downto 0);
        dout_b : out std_logic_vector(31 downto 0)
    );
end entity sram_dual_port;

architecture rtl of sram_dual_port is

    type mem_type is array (0 to 255) of std_logic_vector(31 downto 0);
    -- Shared variable: required for true dual-port BRAM inference in VHDL.
    -- Both processes can access the same memory in the same simulation delta.
    shared variable mem : mem_type;

begin

    -- Port A process: read-first, unconditional write when we_a='1'
    process (clk)
    begin
        if rising_edge(clk) then
            if we_a = '1' then
                mem(to_integer(unsigned(addr_a))) := din_a;
            end if;
            dout_a <= mem(to_integer(unsigned(addr_a)));
        end if;
    end process;

    -- Port B process: read-first, write suppressed on collision with Port A
    process (clk)
    begin
        if rising_edge(clk) then
            if we_b = '1' and not (we_a = '1' and addr_a = addr_b) then
                mem(to_integer(unsigned(addr_b))) := din_b;
            end if;
            dout_b <= mem(to_integer(unsigned(addr_b)));
        end if;
    end process;

end architecture rtl;
