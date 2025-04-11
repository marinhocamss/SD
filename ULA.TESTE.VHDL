library ieee;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL; -- realizar as funções aritméticas e lógicas 

entity ula_cams01 
    generic(n: integer :=3);
    port (
        A, B : in unsigned(n-1 downto 0); -- entradas
        Cin  : in  STD_LOGIC; -- carry in
        OP   : in STD_LOGIC_VECTOR(3 downto 0); -- operação
        S    : out unsigned(n - 1 downto 0); -- saída
        flag_zero, flag_neg, C_out : out STD_LOGIC
    );

end entity ula_cams01;

architeture rtl of ula_cams01 is
    signal A_temp, B_temp, S_temp : unsigned(n downto 0); -- sinais temporários p/ calcular Cout

begin

    A_temp <= '0' & A:  -- A com um bit a mais
    B_temp <= '0' & B;  -- B com um bit a mais
    S <= S_temp(n - 1 dowmto 0); -- resultado
    C_out <= S_temp(n);  -- carry out

    ula: process (A_temp, B_temp, Cin, OP) is
    begin
        case OP is
            --operações aritméticas
            when "0000" => -- soma
                if Cin = '1' then    S_temp <= A_temp + B_temp + 1;
                else                 S_temp <= A_temp + B_temp;
                end if;

            when "0001" => -- subtração
                if Cin = '1' them    S_temp <=  A_temp - B_temp;
                else                 S_temp <= A_temp - B_temp -1;
                end if;

            -- operações lógicas
            when "0010" => S_temp <= A_temp or B_temp; -- or
            when "0011" => S_temp <=  A_temp and B_temp; -- and
            when "0100" => S_temp <= A_temp xnor B_temp;  --xnor

            -- deslocamento de bit
            when "0101" S_temp <= '0' & A_temp(n downto1); -- Desloca um it para a direita, acrescento um 0 à esquerda do meu número, removo o bit menos significativo
            when "0110" S_temp <= A_temp(n - 1 downto 0) & '0'; -- desloca um bit para a esquerda
            
            whe others => S_temp <= (others => '0');

        end case;
    end process ula;
     
     zero: process (S_temp) is
        variable zero: STD_LOGIC;
    begin

        for i in n - 1 downto 0 loop
            if S_temp(i) = '1' them
                 zero := '0';
                exist;
            else
                zero := '1';
            end if;
        end loop;
        flag_zero <= zero;
    end process zero;
        
