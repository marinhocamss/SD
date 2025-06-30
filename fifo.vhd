-- O fifo age como um "buffer" que segura os dados recebidos até que o sistema principal esteja pronto para processá-los.

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity fifo is                                --Com W = 2, a FIFO comporta 4 elementos. Com B = 8, cada elemento tem 8 bits (1 byte).
   generic(
      b: natural := 8; -- número de bits
      w: natural := 4  -- número de bits de endereço → profundidade = 2^w
   );
   port(
      clk, reset: in std_logic;
      rd, wr: in std_logic;
      w_data: in std_logic_vector(b-1 downto 0);  --dado de entrada
      empty, full: out std_logic;
      r_data: out std_logic_vector(b-1 downto 0) --dado de saída
   );
end fifo;

architecture arch of fifo is
   type reg_file_type is array (2**w - 1 downto 0) of  --Cria a memória da FIFO como um vetor de vetores (2^W posições de B bits cada).
        std_logic_vector(b-1 downto 0);
   signal array_reg: reg_file_type;

   signal w_ptr_reg, w_ptr_next, w_ptr_succ:         --São os ponteiros de escrita e leitura (endereços da FIFO).
      std_logic_vector(w-1 downto 0);
   signal r_ptr_reg, r_ptr_next, r_ptr_succ:
      std_logic_vector(w-1 downto 0);

   signal full_reg, empty_reg, full_next, empty_next: --Flags internas da FIFO.
          std_logic;
   signal wr_op: std_logic_vector(1 downto 0);
   signal wr_en: std_logic;                          --Ativa escrita apenas se FIFO não estiver cheia.
begin


  
   --=================================================
   -- REGISTRO DE DADOS (MEMÓRIA)
   --=================================================
  
   process(clk, reset)
   begin                                                      --Grava W_DATA na posição indicada por W_PTR_REG, somente se não estiver cheia.
     if (reset = '1') then
        array_reg <= (others => (others => '0'));
     elsif (clk'event and clk = '1') then
        if wr_en = '1' then
           array_reg(to_integer(unsigned(w_ptr_reg)))
                 <= w_data;
        end if;
     end if;
   end process;
       
   -- leitura combinacional
   r_data <= array_reg(to_integer(unsigned(r_ptr_reg)));

   -- escrita apenas se fifo não estiver cheia
   wr_en <= wr and (not full_reg);


       
   --=================================================
   -- LÓGICA DE CONTROLE FIFO
   --=================================================
       
   process(clk, reset)                                --Atualiza os ponteiros e flags em cada ciclo de clock, ou zera tudo no reset.
   begin
      if (reset = '1') then
         w_ptr_reg <= (others => '0');
         r_ptr_reg <= (others => '0');
         full_reg <= '0';
         empty_reg <= '1';
      elsif (clk'event and clk = '1') then
         w_ptr_reg <= w_ptr_next;
         r_ptr_reg <= r_ptr_next;
         full_reg <= full_next;
         empty_reg <= empty_next;
      end if;
   end process;

   -- incrementos circulares
   w_ptr_succ <= std_logic_vector(unsigned(w_ptr_reg) + 1);
   r_ptr_succ <= std_logic_vector(unsigned(r_ptr_reg) + 1);

   -- lógica de próximo estado
   wr_op <= wr & rd;
   process(w_ptr_reg, w_ptr_succ, r_ptr_reg, r_ptr_succ, wr_op,
           empty_reg, full_reg)
   begin
      w_ptr_next <= w_ptr_reg;
      r_ptr_next <= r_ptr_reg;
      full_next <= full_reg;
      empty_next <= empty_reg;

      case wr_op is
         when "00" => -- nenhuma operação
            null;
         when "01" => -- leitura
            if (empty_reg /= '1') then
               r_ptr_next <= r_ptr_succ;
               full_next <= '0';
               if (r_ptr_succ = w_ptr_reg) then
                  empty_next <= '1';
               end if;
            end if;
         when "10" => -- escrita
            if (full_reg /= '1') then
               w_ptr_next <= w_ptr_succ;
               empty_next <= '0';
               if (w_ptr_succ = r_ptr_reg) then
                  full_next <= '1';
               end if;
            end if;
         when others => -- leitura + escrita simultânea
            w_ptr_next <= w_ptr_succ;
            r_ptr_next <= r_ptr_succ;
      end case;
   end process;

   -- saídas
   full <= full_reg;
   empty <= empty_reg;
end arch;
