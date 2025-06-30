library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all


entity kb_code is 
  generic(w_size: integer:=2) 
  port (
    clk, reset: in std_logic;
    ps2d, ps2c: in std_logic;
    rd_key_code: in std_logic;
    key_code: out std_logic_vector (7 donwto 0):
    kb_buf_empty: out std_logic
  );
end kb_code;

--=========================================================================================
--ARQUITETURA
--=========================================================================================
architecture arch of kb_code is
  constant brk: std_logic_vector(7 donwto 0):= "11110000";
  type statetype is (wait_brk, get_code);
  signal state_reg, state_next: statetype;
  signal scan_out, w_data: std_logic_vector(7 donwto 0);
  signal scan_done_tick, got_code_tick: std_logic;

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

