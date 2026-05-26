-------------------------------------------------------------------------------
-- Module: sram_single_port
-- Description: Single-port SRAM array — 256 rows x 32-bit words.
--              Synchronous read and write on rising clock edge.
--              Coded for BRAM inference (registered output, no reset on memory).
--
-- BRAM Inference (Xilinx UG901 / Intel style):
--   - Signal type for memory declared with shared/signal array
--   - Read registered inside clocked process
--   - No asynchronous read
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity sram_single_port is
    port (
        clk  : in  std_logic;                        -- System clock
        we   : in  std_logic;                        -- Write enable
        addr : in  std_logic_vector(7 downto 0);     -- Address (256 rows)
        din  : in  std_logic_vector(31 downto 0);    -- Data input
        dout : out std_logic_vector(31 downto 0)     -- Data output (registered)
    );
end entity sram_single_port;

architecture rtl of sram_single_port is

    -- Memory type and array: 256 x 32-bit
    type mem_type is array (0 to 255) of std_logic_vector(31 downto 0);
    signal mem : mem_type;

begin

    -- Synchronous read-first process
    -- Write: if we='1', store din at addressed location
    -- Read:  dout always gets mem(addr) — old value on simultaneous write (read-first)
    process (clk)
    begin
        if rising_edge(clk) then
            if we = '1' then
                mem(to_integer(unsigned(addr))) <= din;
            end if;
            dout <= mem(to_integer(unsigned(addr)));
        end if;
    end process;

end architecture rtl;
