library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all


entity kb_code is 
  generic(w_size: integer:=2) --determina a profundidade da FIFO (2^W_SIZE palavras). Com 2 → até 4 teclas na fila.
  port (
    clk, reset: in std_logic;
    ps2d, ps2c: in std_logic;                          -- sinais do teclado PS/2 (dados e clock).
    rd_key_code: in std_logic;                         --usado pelo sistema principal para ler uma tecla.
    key_code: out std_logic_vector (7 donwto 0):       -- código da tecla mais recentemente liberada.
    kb_buf_empty: out std_logic;                       --sinaliza se a FIFO está vazia (nenhuma tecla disponível).
  );
end kb_code;

--=========================================================================================
--ARQUITETURA
--=========================================================================================
architecture arch of kb_code is
  constant brk: std_logic_vector(7 donwto 0):= "11110000";              --código F0 que sinaliza que uma tecla foi liberada.
  type statetype is (wait_brk, get_code);
  signal state_reg, state_next: statetype;                              --registradores da FSM (estado atual e próximo).
  signal scan_out, w_data: std_logic_vector(7 donwto 0);                --SCAN_OUT: dado (1 byte) vindo do teclado, recebido pelo ps2_rx. W_DATA:dado a ser escrito na FIFO.
  signal scan_done_tick, got_code_tick: std_logic;                      --SCAN_DONE_TICK: sinaliza que um byte foi recebido de ps2_rx. GOT_CODE_TICK: pulso que habilita gravação na FIFO

begin


--=========================================================================================
--INSTANCIAR
--=========================================================================================

  ps2_rx_unit: entity work.ps2_rx(arch)
    port map(clk=>clk,
             reset=>reset,
             rx_en=>'1',
             ps2d=>ps2d,
             ps2c=>ps2c,
             rx_done_tick=>scan_done_tick,
             dout=>scan_out);

    --Esse bloco acima: (1)Sempre habilita a recepção (RX_EN = '1'). 
    --(2)Recebe os bits PS/2 e emite um byte (DOUT) quando o byte completo estiver pronto (RX_DONE_TICK = '1').
    --(3)O byte é salvo em SCAN_OUT


 fifo_key_unit: entity work.fifo(arch)
   generic map(b=>8, w=>w_size)
   port map(clk=>clk,
            reset=>reset,
            rd=>rd_key_code,
            wr=>got_code_tick,
            w_data=>scan_out,
            empty=>kb_buf_empty,
            full=>open,
            r_data=>key_code);
   
  --Essa fifo: (1)Armazena até 2^W_SIZE códigos de tecla liberada. (2)Escreve quando GOT_CODE_TICK = '1'. (3)Lê quando RD_KEY_CODE = '1'.
  --Saída:(1)KEY_CODE: byte mais recente. (2)KB_BUF_EMPTY: indica se há dados disponíveis.



--=========================================================================================
--MAQUINA DE ESTADOS E SEUS PERIODOS
--=========================================================================================   
  process (clk, reset)
  begin
    if reset='1' then
      state_reg <= wait_brk;
    elsif (clk'event and clk='1') then
      state_reg <= state_next;
    end if;
  end process;
--Esse bloco: Inicializa no estado WAIT_BRK e transiciona em borda de subida do clock.

      
  process(state_reg, scan_done_tick, scan_out)
  begin
    got_code_tick <= '0';
    state_next <= state_reg;
    case state_reg is
      when wait_brk =>
        if scan_done_tick='1' and scan_out=brk then
          state_next <= get_code;
        end if;
      when get_code =>
        if scan_done_tick='1' then 
           got_code_tick <='1';
           state_next <= wait_brk;
        end if;
    end case;
  end process;
end arch;

--WAIT_BRK: espera o byte F0 (break code). 
--GET_CODE: pega o próximo byte como o código da tecla liberada.
--GOT_CODE_TICK = '1': ativa escrita na FIFO.
