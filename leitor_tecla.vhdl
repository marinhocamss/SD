--Lê os códigos de tecla liberada do teclado PS/2.
--Usa o componente KB_CODE.
--Usa uma máquina de estados (FSM) para:
--Aguarda a chegada de uma tecla (EINICIAL);
--Ler a tecla do buffer (EMEIO);
--Liberar o buffer para próxima leitura (EFINAL).
--Exibe o código da tecla nos LEDs.
--Pode sinalizar que uma tecla foi lida via TECLOU



library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity leitor_tecla is
    port (
        clk, reset   : in  std_logic;                       -- ENTRADAS DE CLOCK E RESET
        ps2d, ps2c   : in  std_logic;                       -- ENTRADAS DE DADOS E CLOCK PS2
        leds         : out std_logic_vector(7 downto 0);    -- SAIDA PARA OS LEDS
        teclou       : out std_logic                        -- SAIDA PARA INDICAR TECLA PRESSIONADA                           
    );
end leitor_tecla;

architecture behavioral of leitor_tecla is

    component kb_code
        port (
            clk, reset      : in  std_logic;                            -- ENTRADAS DE CLOCK E RESET
            ps2d, ps2c      : in  std_logic;                            -- ENTRADAS DE DADOS E CLOCK PS2
            rd_key_code     : in  std_logic;                            -- ENTRADA PARA LER CODIGO DA TECLA
            key_code        : out std_logic_vector(7 downto 0);         -- SAIDA DO CODIGO DA TECLA
            kb_buf_empty    : out std_logic                             -- SAIDA INDICANDO BUFFER DO TECLADO VAZIO
        );
    end component;
    
    type estados is (
        einicial,                    --ESTADO INICIAL
        emeio,                       --ESTADO INTERMEDIARIO
        efinal                       -- ESTADO FINAL
    );
    
    signal eatual       : estados := einicial;          -- SINAL PARA O ESTADO ATUAL
    signal eproximo     : estados;                      -- SINAL PARA O PROXIMO ESTADO
    signal liberabuf    : std_logic := '0';             -- SINAL PARA LIBERAR BUFFER
    signal keyread      : std_logic_vector(7 downto 0) := "00000000";       -- SINAL PARA LEITURA DA TECLA
    signal keybuffer    : std_logic_vector(7 downto 0);  	                  -- SINAL PARA BUFFER DA TECLA
    signal bufempty     : std_logic;                                        -- SINAL INDICANDO BUFFER VAZIO
    signal clkreduzido  : std_logic := '0';                               	-- SINAL DO CLOCK REDUZIDO

begin

    kbc: kb_code                                                    -- MAPEAMENTO DO COMPONENTE KB_CODE
        port map (
            clk, reset, ps2d, ps2c, liberabuf, keybuffer, bufempty
        );
    leds <= keyread;                                      -- LEDS EXIBEM A TECLA LIDA


    --===================================================
    -- REDUTOR DE CLOCK
    --==================================================
    process(clk)
        variable contagem : unsigned(5 downto 0) := "000000";         -- VARIAVEL PARA CONTAGEM
    begin
        if (clk = '1' and clk'event) then                              
            if (contagem >= 9) then                                    -- SE A CONTAGEM ATINGIR 9
                contagem := "000000";                                  -- RESETA A CONTAGEM
                clkreduzido <= not clkreduzido;                        -- INVERTE O CLOCK REDUZIDO
            else
                contagem := contagem + 1;                              -- INCREMENTA A CONTAGEM
            end if;
        end if;
    end process;

    --==============================================================
    --CONTROLE DE DESTADOS
    --==============================================================
            
    process(clkreduzido, eatual, bufempty)                                      
    begin
        if (clkreduzido = '1' and clkreduzido'event) then                    
            if eatual = einicial then                        -- SE ESTIVER NO ESTADO INICIAL
                if bufempty = '0' then                       -- SE O BUFFER NAO ESTIVER VAZIO
                    eatual <= emeio;                         -- VAI PARA O ESTADO INTERMEDIARIO
                end if;
            end if;

            if eatual = emeio then                           -- SE ESTIVER NO ESTADO INTERMEDIARIO
                eatual <= efinal;                            -- VAI PARA O ESTADO FINAL
            end if;

            if eatual = efinal then                             -- SE ESTIVER NO ESTADO FINAL
                eatual <= einicial;                              -- VOLTA PARA O ESTADO INICIAL
            end if;
        end if;
    end process;

            
    --=================================================
    -- AÇÕES EM CADA ESTADO
    --=================================================
            
    process(clkreduzido)
    begin
        if eatual = einicial then            -- SE ESTIVER NO ESTADO INICIAL
            liberabuf <= '0';                -- NAO LIBERA O BUFFER
        end if;

        if eatual = emeio then               -- SE ESTIVER NO ESTADO INTERMEDIARIO
            keyread <= keybuffer;            ---- LE O BUFFER DA TECLA
        end if;

        if eatual = efinal then        -- SE ESTIVER NO ESTADO FINAL
            liberabuf <= '1';          -- LIBERA O BUFFER
        end if;
    end process;

end behavioral;
