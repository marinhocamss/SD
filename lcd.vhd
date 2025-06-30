--OBJ. do lcd:
--Controlar o display LCD para mostrar informações, enviando comandos e dados com o timing correto.
--Ler dados do teclado PS/2 para interagir com o jogo.
--Implementar um jogo da forca básico:
--A palavra “projeto” está "escondida" com pontos no display.
--Quando o jogador digita uma letra correta no teclado, ela aparece no LCD.
--Ao errar demais, aparece uma mensagem de "HAHAHA" (perdeu).
--Controlar os estados e temporizações necessárias para a comunicação correta com o LCD e a leitura do teclado.



library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_ARITH.all;
use IEEE.STD_LOGIC_UNSIGNED.all;

entity lcd is
    port(
        lcd_db: out std_logic_vector(7 downto 0); -- dados para o display lcd
        rs: out std_logic;  -- registro select: 0 comando, 1 dado
        rw: out std_logic;  -- read/write: 0 escreve, 1 lê
        clk: in std_logic;  -- clock do sistema
        oe: out std_logic;  -- output enable para controle do lcd
        rst: in std_logic;  -- reset síncrono
        leds : out std_logic_vector (7 downto 0); -- leds indicadores para debug
        ps2d, ps2c: in std_logic  -- dados e clock do teclado ps2
    );
end lcd;

architecture behavioral of lcd is

--==================================================================
-- DEFINIÇÃO DOS COMPONENTES
--=====================================================================
component kb_code port(
    clk, reset: in std_logic; -- clock e reset do fpga
    ps2d, ps2c: in std_logic;  -- interface ps2
    rd_key_code: in std_logic; -- sinal para liberar leitura do buffer
    key_code: out std_logic_vector(7 downto 0); -- código da tecla lida
    kb_buf_empty: out std_logic -- sinal indicando buffer vazio
);
end component kb_code;

--=========================================================
--  DEFINIÇÕES DE TIPOS DE SINAIS
--=============================================================

-- estados da máquina de controle principal do lcd
type mstate is (
    stfunctionset,		 	
    stdisplayctrlset,
    stdisplayclear,
    stpoweron_delay,  				
    stfunctionset_delay,
    stdisplayctrlset_delay, 	
    stdisplayclear_delay,
    stinitdne,				
    stactwr,
    stchardelay
);

-- estados da máquina de controle da escrita no lcd
type wstate is (
    strw,						
    stenable,				
    stidle
);

-- estados do jogo (espera, acerto, erro, perdeu)
type jestados is (
    jespera,
    jacerto,
    jerro,
    jperde
);

-- estados do leitor do buffer do teclado
type mleitor is (
    minicial,
    mmeio,
    mfinal
);

-- sinais de controle e dados internos
signal clkcount: std_logic_vector(5 downto 0);                      -- contador para gerar pulso de 1us
signal activatew: std_logic := '0';                                 -- habilita escrita no lcd
signal count: std_logic_vector(16 downto 0) := (others => '0');     -- contador para delays maiores
signal delayok: std_logic := '0';                                   -- sinalizador de término do delay atual
signal oneusclk: std_logic;                                         -- pulso com período de 1us para temporização

signal stcur: mstate := stpoweron_delay;                             -- estado atual da máquina principal do lcd
signal stnext: mstate;                                               -- próximo estado da máquina principal do lcd

signal stcurw: wstate := stidle;                                     -- estado atual da máquina de controle de escrita
signal stnextw: wstate;                                              -- próximo estado da máquina de controle de escrita

signal lcd_cmd_ptr: integer range 0 to 14 := 0;                      -- ponteiro para comandos da lcd

signal writedone: std_logic := '0';                                  -- sinaliza que terminou de enviar comandos para o lcd

-- sinais para interface com teclado ps2
signal liberabuf: std_logic := '0';                                      -- libera leitura do buffer do teclado
signal keyread: std_logic_vector(7 downto 0) := (others => '0');         -- tecla lida pelo sistema
signal keybuffer: std_logic_vector(7 downto 0);                          -- tecla armazenada no buffer do teclado
signal bufempty: std_logic;                                              -- indica se o buffer do teclado está vazio

-- controle do jogo da forca
signal errocount: unsigned(3 downto 0) := (others => '0');                 -- contador de erros
signal teclou: std_logic := '0';                                           -- sinaliza que uma tecla foi lida
signal leu: std_logic := '0';                                              -- sinaliza que a leitura da tecla foi consumida

type show_t is array (integer range 0 to 5) of std_logic_vector(9 downto 0);
signal show: show_t := (
    0 => "10" & x"2e",                                                       -- inicializa com pontos para esconder palavra
    1 => "10" & x"2e",
    2 => "10" & x"2e",
    3 => "10" & x"2e",
    4 => "10" & x"2e",
    5 => "10" & x"2e"
);

-- comandos para o lcd (função e caracteres)
type lcd_cmds_t is array(integer range 0 to 13) of std_logic_vector(9 downto 0);
signal lcd_cmds: lcd_cmds_t := (
    0 => "00" & x"3c",                     -- função set lcd
    1 => "00" & x"0c",                     -- display on, cursor off, blink off
    2 => "00" & x"01",                     -- limpa display
    3 => "00" & x"02",                     -- return home
    4 => "10" & x"48",                     -- H (exemplo de caractere)
    5 => "10" & x"65",                     -- E
    6 => "10" & x"6c",                     -- L
    7 => "10" & x"6c",                     -- L
    8 => "10" & x"6f",                     -- O
    9 => "10" & x"20",                     -- espaço
    10 => "10" & x"46",                    -- F
    11 => "10" & x"72",                    -- R
    12 => "10" & x"72",                    -- R
    13 => "10" & x"72"                     -- R
);

begin

-- leds indicam o código da tecla lida (para debug)
leds <= keyread;

-- atualiza comandos da lcd com a palavra a ser mostrada (ex: projeto)
lcd_cmds(4) <= show(0);
lcd_cmds(5) <= show(1);
lcd_cmds(6) <= show(2);
lcd_cmds(7) <= show(3);
lcd_cmds(8) <= show(4);
lcd_cmds(9) <= show(5);
lcd_cmds(10) <= show(2);

-- instanciando o componente de leitura do teclado ps2
kbc: kb_code port map(clk, rst, ps2d, ps2c, liberabuf, keybuffer, bufempty);

-- contador para gerar pulso de 1us a partir do clock principal
process(clk)
begin
    if rising_edge(clk) then
        clkcount <= clkcount + 1;
    end if;
end process;

oneusclk <= clkcount(5);                                                -- pulso 1us gerado a partir do bit 5 do contador

-- contador para delays, resetado quando delayok=1
process(oneusclk, delayok)
begin
    if rising_edge(oneusclk) then
        if delayok = '1' then
            count <= (others => '0');
        else
            count <= count + 1;
        end if;
    end if;
end process;

-- indica quando terminou de enviar todos os comandos para o lcd
writedone <= '1' when lcd_cmd_ptr = lcd_cmds'high else '0';

-- controla o ponteiro dos comandos lcd (lcd_cmd_ptr)
process(lcd_cmd_ptr, oneusclk)
begin
    if rising_edge(oneusclk) then
        if (stnext = stinitdne or stnext = stdisplayctrlset or stnext = stdisplayclear) and writedone = '0' then
            lcd_cmd_ptr <= lcd_cmd_ptr + 1;                                            -- passa para próximo comando
        elsif stcur = stpoweron_delay or stnext = stpoweron_delay then
            lcd_cmd_ptr <= 0;                                                          -- reseta ponteiro no reset inicial
        elsif teclou = '1' then
            lcd_cmd_ptr <= 3;                                                          -- comando específico quando tecla foi pressionada
        else
            lcd_cmd_ptr <= lcd_cmd_ptr;                                                -- mantém ponteiro
        end if;
    end if;
end process;

-- sinal delayok ativo quando contagem atingir valores específicos de delay por estado
delayok <= '1' when (
    (stcur = stpoweron_delay and count = "00100111001010010") or   
    (stcur = stfunctionset_delay and count = "00000000000110010") or
    (stcur = stdisplayctrlset_delay and count = "00000000000110010") or
    (stcur = stdisplayclear_delay and count = "00000011001000000") or
    (stcur = stchardelay and count = "11111111111111111")
) else '0';

-- máquina principal do lcd: controla sequência de comandos e delays
process(oneusclk, rst)
begin
    if rising_edge(oneusclk) then
        if rst = '1' then
            stcur <= stpoweron_delay;                                                 -- estado inicial no reset
        else
            stcur <= stnext;                                                          -- avança para próximo estado
        end if;
    end if;
end process;

-- controle da saída de sinais para o lcd conforme o estado da máquina principal
process(stcur, delayok, writedone, lcd_cmd_ptr)
begin
    case stcur is
        when stpoweron_delay =>
            if delayok = '1' then
                stnext <= stfunctionset;                                                          -- após delay inicial vai para função set
            else
                stnext <= stpoweron_delay;
            end if;
            -- sinaliza para o lcd os bits do comando atual
            rs <= lcd_cmds(lcd_cmd_ptr)(9);
            rw <= lcd_cmds(lcd_cmd_ptr)(8);
            lcd_db <= lcd_cmds(lcd_cmd_ptr)(7 downto 0);
            activatew <= '0'; -- desativa escrita neste estado

        when stfunctionset =>
            rs <= lcd_cmds(lcd_cmd_ptr)(9);
            rw <= lcd_cmds(lcd_cmd_ptr)(8);
            lcd_db <= lcd_cmds(lcd_cmd_ptr)(7 downto 0);
            activatew <= '1';	-- ativa escrita
            stnext <= stfunctionset_delay;

        when stfunctionset_delay =>
            rs <= lcd_cmds(lcd_cmd_ptr)(9);
            rw <= lcd_cmds(lcd_cmd_ptr)(8);
            lcd_db <= lcd_cmds(lcd_cmd_ptr)(7 downto 0);
            activatew <= '0'; -- desativa escrita para aguardar delay
            if delayok = '1' then
                stnext <= stdisplayctrlset;
            else
                stnext <= stfunctionset_delay;
            end if;

        when stdisplayctrlset =>
            rs <= lcd_cmds(lcd_cmd_ptr)(9);
            rw <= lcd_cmds(lcd_cmd_ptr)(8);
            lcd_db <= lcd_cmds(lcd_cmd_ptr)(7 downto 0);
            activatew <= '1'; -- ativa escrita
            stnext <= stdisplayctrlset_delay;

        when stdisplayctrlset_delay =>
            rs <= lcd_cmds(lcd_cmd_ptr)(9);
            rw <= lcd_cmds(lcd_cmd_ptr)(8);
            lcd_db <= lcd_cmds(lcd_cmd_ptr)(7 downto 0);
            activatew <= '0'; -- espera delay
            if delayok = '1' then
                stnext <= stdisplayclear;
            else
                stnext <= stdisplayctrlset_delay;
            end if;

        when stdisplayclear	=>
            rs <= lcd_cmds(lcd_cmd_ptr)(9);
            rw <= lcd_cmds(lcd_cmd_ptr)(8);
            lcd_db <= lcd_cmds(lcd_cmd_ptr)(7 downto 0);
            activatew <= '1'; -- ativa escrita
            stnext <= stdisplayclear_delay;

        when stdisplayclear_delay =>
            rs <= lcd_cmds(lcd_cmd_ptr)(9);
            rw <= lcd_cmds(lcd_cmd_ptr)(8);
            lcd_db <= lcd_cmds(lcd_cmd_ptr)(7 downto 0);
            activatew <= '0'; -- espera delay
            if delayok = '1' then
                stnext <= stinitdne;
            else
                stnext <= stdisplayclear_delay;
            end if;

        when stinitdne =>		
            rs <= lcd_cmds(lcd_cmd_ptr)(9);
            rw <= lcd_cmds(lcd_cmd_ptr)(8);
            lcd_db <= lcd_cmds(lcd_cmd_ptr)(7 downto 0);
            activatew <= '0';
            stnext <= stactwr;

        when stactwr =>		
            rs <= lcd_cmds(lcd_cmd_ptr)(9);
            rw <= lcd_cmds(lcd_cmd_ptr)(8);
            lcd_db <= lcd_cmds(lcd_cmd_ptr)(7 downto 0);
            activatew <= '1'; -- ativa escrita do caractere
            stnext <= stchardelay;

        when stchardelay =>
            rs <= lcd_cmds(lcd_cmd_ptr)(9);
            rw <= lcd_cmds(lcd_cmd_ptr)(8);
            lcd_db <= lcd_cmds(lcd_cmd_ptr)(7 downto 0);
            activatew <= '0';	-- espera delay		
            if delayok = '1' then
                stnext <= stinitdne; -- volta para enviar próximo caractere
            else
                stnext <= stchardelay;
            end if;
    end case;
end process;					

-- máquina de controle do pulso OE (output enable) para lcd
process(oneusclk, rst)
begin
    if rising_edge(oneusclk) then
        if rst = '1' then
            stcurw <= stidle; -- reset da máquina de escrita
        else
            stcurw <= stnextw; -- avança estado
        end if;
    end if;
end process;

process(stcurw, activatew)
begin   
    case stcurw is
        when strw =>
            oe <= '0'; -- desabilita saída para setup
            stnextw <= stenable;
        when stenable => 
            oe <= '0'; -- mantem saída desabilitada durante escrita
            stnextw <= stidle;
        when stidle =>
            oe <= '1'; -- ativa saída lcd
            if activatew = '1' then
                stnextw <= strw; -- se precisa escrever, volta para início
            else
                stnextw <= stidle; -- fica aguardando
            end if;
    end case;
end process;

--- lógica do jogo da forca (atualiza palavra oculta e erros)
process(rst, oneusclk, teclou, keyread)
begin
    -- inicializa palavra oculta e reseta contador de erros
    if rst = '1' then
        show <= (others => "10" & x"2e"); -- pontos para ocultar palavra
        errocount <= (others => '0');

    elsif rising_edge(oneusclk) then
        -- se errou mais que 3 vezes (limite), mostra "HAHAHA"
        if errocount >= 3 then
            show(0) <= "10"&x"48"; -- h
            show(1) <= "10"&x"41"; -- a
            show(2) <= "10"&x"48"; -- h
            show(3) <= "10"&x"41"; -- a
            show(4) <= "10"&x"48"; -- h
            show(5) <= "10"&x"41"; -- a

        elsif teclou = '1' then
            -- decodifica tecla pressionada e atualiza as letras da palavra "projeto"
            case keyread is
                when "01001101" => -- P
                    show(0) <= "10"&x"50";
                    show(1 to 5) <= show(1 to 5);
                when "00101101" => -- R
                    show(1) <= "10"&x"52";
                    show(0) <= show(0);
                    show(2 to 5) <= show(2 to 5);
                when "01000100" => -- O
                    show(2) <= "10"&x"4f";
                    show(0 to 1) <= show(0 to 1);
                    show(3 to 5) <= show(3 to 5);
                when "00111011" => -- J
                    show(3) <= "10"&x"4a";
                    show(0 to 2) <= show(0 to 2);
                    show(4 to 5) <= show(4 to 5);
                when "00100100" => -- E
                    show(4) <= "10"&x"45";
                    show(0 to 3) <= show(0 to 3);
                    show(5) <= show(5);
                when "00101100" => -- T
                    show(5) <= "10"&x"54";
                    show(0 to 4) <= show(0 to 4);
                when others =>
                    errocount <= errocount + 1; -- incrementa contador de erros para tecla inválida
                    show(0 to 5) <= show(0 to 5);
            end case;
            leu <= '1';	-- sinaliza que a tecla foi lida e processada
        else
            show <= show; -- mantém estado atual se nenhuma tecla pressionada
        end if;
    end if;
end process;

-- máquina para controle de leitura do buffer do teclado
process(oneusclk)
begin
    if rising_edge(oneusclk) then
        case matual is
            when minicial =>
                if bufempty = '0' then -- buffer com dados para ler
                    matual <= mmeio;
                end if;

            when mmeio =>
                if leu = '1' then
                    matual <= mfinal;
                end if;

            when mfinal =>
                matual <= minicial;
        end case;
    end if;
end process;

-- controle dos sinais de leitura do teclado (liberação e flags)
process(oneusclk)
begin
    if rising_edge(oneusclk) then
        case matual is
            when minicial =>
                liberabuf <= '0'; -- não libera leitura do buffer ainda
            when mmeio =>
                teclou <= '1'; -- sinaliza que tecla foi lida
                keyread <= keybuffer; -- atualiza tecla lida
            when mfinal =>
                teclou <= '0'; -- reseta sinalização de tecla lida
                leu <= '0'; -- reseta sinal de consumo da tecla
                liberabuf <= '1'; -- libera próxima leitura do buffer
        end case;
    end if;
end process;

end behavioral;
