library ieee;
use ieee.std_logic_1164.all;
USE ieee.numeric_std.ALL; 
library grlib;
use grlib.amba.all;
use grlib.stdlib.all;
use grlib.devices.all;
library techmap;
use techmap.gencomp.all;
library gaisler;
library top;
use top.config.all;
library ina;
library ina_pkg;
use ina_pkg.ina_config.all;

entity crm_config is
    generic (
        max_tile_cr : integer := 8;
        abit : integer;
        dbit : integer
    );
    port (
        rst             : in  std_ulogic;
        clk             : in  std_ulogic;
        r_addr          : out  std_logic_vector((abit - 1) downto 0);
        r_data_rd       : in std_logic_vector((dbit -1) downto 0); -- max tile cr 8
        r_data_wr       : out std_logic_vector((dbit -1) downto 0); -- max tile cr 8
        r_enable        : out std_logic;
        r_write         : out std_logic;
        r_req           : out std_logic;
        r_gnt           : in  std_logic;
-----------reading---------------
        fifo_rd_en      : out  STD_ULOGIC;
        fifo_data_in    : in  STD_LOGIC_VECTOR ((64- 1) downto 0);
        fifo_empty      : in STD_ULOGIC;
        fifo_wr_en      : out  STD_ULOGIC;
        fifo_data_out   : out STD_LOGIC_VECTOR ((32 - 1) downto 0);
        fifo_full	: in STD_ULOGIC
    );
end; 

architecture rtl of crm_config is

type state_type is (s0,s1,s1a,s2,s3,s3a,s4,s5,s6,s6a,s7,s8);  --type of state machine.
signal current_s,next_s: state_type;  --current and next state declaration.
signal start_addr, counter, end_addr : integer; 
signal old_st, new_st : std_logic_vector(31 downto 0);
--signal data_req : std_logic_vector(63 downto 0);
signal update_req ,update_old_new, run_flag, data_flag: std_ulogic;
constant zero_32 : std_logic_vector(31 downto 0) := (others => '0');

function ram_update(old_st : std_logic_vector(31 downto 0); new_st : std_logic_vector(31 downto 0); data : std_logic_vector((dbit - 1) downto 0)) return std_logic_vector is
variable new_data, old_data: std_logic_vector((max_tile_cr -2) downto 0);
variable j1 : integer := 0;
variable j2 : integer := 0;
begin
    new_data := (others => '0');
    old_data := data((max_tile_cr -2) downto 0);

    for i in 0 to 31 loop
        if old_st(i) = '1' and new_st(i) = '1' then
            new_data(j2) := old_data(j1);
	end if;

	if old_st(i) = '1' then
            j1 := j1 + 1;
	end if;
	
	if new_st(i) = '1' then
            j2 := j2 + 1;
	end if;
	
        if (j2 >= (max_tile_cr-1) or j1 >= (max_tile_cr-1)) then
            return data(max_tile_cr) & '1' & new_data;
	end if;
    end loop;

    return data((max_tile_cr) downto (max_tile_cr-1)) & new_data;
end function ram_update;

begin

pro_state : process (clk,rst)  
begin
    if  (rst /= '1') then
        --flag <= '0';
	current_s <= s0;	
    elsif(clk='1' and clk'Event) then
	current_s <= next_s; 	
    end if;  
end process pro_state;


process(current_s, fifo_empty, counter, fifo_full, r_gnt, fifo_data_in, end_addr)
begin
    case current_s is
        when s0 =>
            if(fifo_empty = '0') then
                next_s <= s1;
            else
                next_s <= s0;
            end if;

        when s1 =>
            next_s <= s1a;

        when s1a =>
            next_s <= s2;

        when s2 =>
            if(fifo_data_in(2 downto 0) = "000" ) then
                next_s <= s3a;
             elsif (fifo_data_in(2 downto 0) = "001" ) then
                next_s <= s4;
             elsif (fifo_data_in(2 downto 0) = "111" and fifo_full = '0') then
                next_s <= s8;
             else
                next_s <= s0;
             end if;

        when s3a =>
            if(r_gnt = '1') then
                next_s <= s3;
            else
                next_s <= s3a;
            end if;

        when s3 =>
            if(r_gnt = '1') then
               if (counter /= end_addr ) then
                    next_s <= s3;
               else
                    next_s <= s0;
               end if;
            else
               next_s <= s3a;
            end if;

        when s4 =>
            if(fifo_empty = '0') then
                next_s <= s5;
            else
                next_s <= s4;
            end if;

        when s5 =>
            next_s <= s6a;

        when s6a =>
            if(r_gnt = '1') then
               next_s <= s6;
            else
                next_s <= s6a;
            end if;

        when s6 =>
            if(r_gnt = '1') then
                 if(counter /= end_addr) then
                    next_s <= s7;
                else
                    next_s <= s0;
                end if;
            else
               next_s <= s6a;
            end if;

        when s7 =>
            next_s <= s6;

        when s8 =>
            next_s <= s0;

        when others =>
            next_s <= s0;
	
    end case;
end process;


process (clk,rst)  
begin
    if (rst /= '1') then

    elsif(clk='1' and clk'Event) then
	if(run_flag = '1') then
            counter <= counter + 1;
	end if;

	if(update_req = '1')then
            --data_req <= fifo_data_in;
            start_addr <= to_integer(unsigned(fifo_data_in(63 downto 46)));
            end_addr <= to_integer(unsigned(fifo_data_in(45 downto 28)));
            counter <= to_integer(unsigned(fifo_data_in(63 downto 46)));
	end if;

	if(update_old_new = '1')then
            old_st <= fifo_data_in(31 downto 0);
            new_st <= fifo_data_in(63 downto 32);
	end if;	
    end if;  
end process;


process(current_s, fifo_data_in)
begin
    fifo_wr_en <= '0';
    fifo_data_out <= (others => '0');
    update_req <= '0'; --
    update_old_new <= '0';
    fifo_rd_en <= '0'; --
    run_flag <= '0'; --
    data_flag <= '0'; --

    case current_s is
        when s0 =>
            r_enable <= '0';
            r_write <= '0';
            r_req <= '0';

        when s1 =>
            fifo_rd_en <= '1';
            r_enable <= '0';
            r_write <= '0';
            update_req <= '0';
            r_req <= '0';

        when s1a =>
            fifo_rd_en <= '0';
            r_enable <= '0';
            r_write <= '0';
            update_req <= '1';
            r_req <= '1';

        when s2 =>
            r_enable <= '0';
            r_write <= '0';
            r_req <= '1';

        when s3 =>
            r_enable <= '1';
            r_write <= '1';
            run_flag <= '1';
            data_flag <= '0';
            r_req <= '1';

        when s3a =>
            r_enable <= '0';
            r_write <= '0';
            run_flag <= '0';
            data_flag <= '0';
            r_req <= '1';

        when s4 =>
            r_enable <= '0';
            r_write <= '0';
            r_req <= '1';

        when s5 =>
            fifo_rd_en <= '1';
            r_enable <= '0';
            r_write <= '0';
            update_old_new <= '0';
            r_req <= '1';

        when s6a =>
            r_enable <= '0';
            r_write <= '0';
            run_flag <= '0';
            update_old_new <= '1';
            data_flag <= '0';
            r_req <= '1';

        when s6 =>
            r_enable <= '1';
            r_write <= '0';
            run_flag <= '0';
            data_flag <= '1';
            r_req <= '1';

        when s7 =>
            r_enable <= '1';
            r_write <= '1';
            run_flag <= '1';
            data_flag <= '1';
            r_req <= '1';

        when s8 =>
            r_enable <= '0';
                r_write <= '0';
                fifo_wr_en <= '1';
                fifo_data_out <= zero_32(31 downto 8) & fifo_data_in(10 downto 3);
                r_req <= '0';

        when others =>
            r_enable <= '0';
            r_write <= '0';
            r_req <= '0';

    end case;
end process;


r_addr <= std_logic_vector(to_unsigned(counter, abit));

r_data_wr <= zero_32((dbit - 1) downto 0) when data_flag = '0' else
             ram_update(old_st, new_st, r_data_rd) when data_flag = '1';

end;

