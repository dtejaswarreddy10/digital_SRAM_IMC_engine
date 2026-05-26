-------------------------------------------------------------------------------
-- Module: imc_compute_unit
-- Description: In-Memory Compute Boolean logic unit — purely combinational.
--              8 bitwise operations, zero flag, and popcount (ones_count).
--
-- Operation Encoding (op_sel):
--   "000" — AND     "001" — OR      "010" — XOR     "011" — NOR
--   "100" — NAND    "101" — XNOR    "110" — NOT A   "111" — PASS A
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity imc_compute_unit is
    port (
        operand_a  : in  std_logic_vector(31 downto 0);  -- Row A data
        operand_b  : in  std_logic_vector(31 downto 0);  -- Row B data
        op_sel     : in  std_logic_vector(2 downto 0);   -- Operation select
        result     : out std_logic_vector(31 downto 0);  -- Compute result
        zero_flag  : out std_logic;                      -- 1 if result = 0
        ones_count : out std_logic_vector(5 downto 0)    -- Popcount (0–32)
    );
end entity imc_compute_unit;

architecture rtl of imc_compute_unit is

    signal result_i : std_logic_vector(31 downto 0);

begin

    -- 8-way operation MUX (combinational)
    process (operand_a, operand_b, op_sel)
    begin
        case op_sel is
            when "000"  => result_i <= operand_a and operand_b;          -- AND
            when "001"  => result_i <= operand_a or  operand_b;          -- OR
            when "010"  => result_i <= operand_a xor operand_b;          -- XOR
            when "011"  => result_i <= not (operand_a or  operand_b);    -- NOR
            when "100"  => result_i <= not (operand_a and operand_b);    -- NAND
            when "101"  => result_i <= not (operand_a xor operand_b);    -- XNOR
            when "110"  => result_i <= not operand_a;                    -- NOT A
            when "111"  => result_i <= operand_a;                        -- PASS A
            when others => result_i <= (others => '0');
        end case;
    end process;

    result <= result_i;

    -- Zero flag: '1' when all result bits are zero
    zero_flag <= '1' when unsigned(result_i) = 0 else '0';

    -- Popcount: count number of 1-bits (adder tree unrolled from loop)
    process (result_i)
        variable count : unsigned(5 downto 0);
    begin
        count := (others => '0');
        for i in 0 to 31 loop
            if result_i(i) = '1' then
                count := count + 1;
            end if;
        end loop;
        ones_count <= std_logic_vector(count);
    end process;

end architecture rtl;
