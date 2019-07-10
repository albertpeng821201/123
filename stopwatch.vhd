library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_logic_ARITH.ALL;
use IEEE.STD_logic_UNSIGNED.ALL;



entity stop_watch is
    Port(
    clk_to_100hz : in std_logic;
    clk :			 in std_logic;
    reset : in std_logic;
	 mode_sw: in std_logic;
    action_imp :    in std_logic;
    mode_imp :      in std_logic;
    minus_imp :     in std_logic;
    plus_imp :      in std_logic;
    plus_minus :    in std_logic;
    csec_count :    out std_logic_vector(7 downto 0);
    sec_count :     out std_logic_vector (7 downto 0);
    min_count :     out std_logic_vector(7 downto 0);
    hour_count :    out std_logic_vector(7 downto 0);
	 freeze_lap:    out std_logic
    );
end stop_watch;

architecture Behavioral of stop_watch is

signal keyboard_focus : std_logic_vector (2 downto 0);

    signal csec_co : std_logic :='0';
    signal sec_co : std_logic :='0';
    signal min_co : std_logic :='0';
	 -- counter
    signal counter_99_csec : std_logic_vector(7 downto 0):= (others => '0');
    signal counter_60_sec : std_logic_vector(7 downto 0) := (others => '0');
    signal counter_60_min : std_logic_vector(7 downto 0) := (others => '0');
    signal counter_99_hour : std_logic_vector(7 downto 0):= (others => '0');
	 --counter for the freeze mode
    signal counter_99_csec_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal counter_60_sec_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal counter_60_min_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal counter_99_hour_reg : std_logic_vector(7 downto 0):= (others => '0');

	 signal freeze_lap_reg : std_logic :='0';

    type state_type is (initial_state,stopwatch_display,counter_start,counter_stop,freeze_display,time_display);
    signal present_state: state_type := initial_state;
    signal next_state:  state_type := initial_state;
-----
begin
	time_output : process(
	present_state,
	counter_99_csec_reg,counter_60_sec_reg,counter_60_min_reg,counter_99_hour_reg,
	counter_99_csec,counter_60_sec,counter_60_min,counter_99_hour,
	freeze_lap_reg
	)-- output the time to display
  begin
		  if(present_state = freeze_display)then --if stopwatch_display shows in freeze show the freeze data
				csec_count <= counter_99_csec_reg;
				sec_count <= counter_60_sec_reg;
				min_count <= counter_60_min_reg;
				hour_count <= counter_99_hour_reg;
		  else
				csec_count <= counter_99_csec;
				sec_count <= counter_60_sec;
				min_count <= counter_60_min;
				hour_count <= counter_99_hour;
		 end if;
		 freeze_lap<=freeze_lap_reg;
	end process time_output;

	counter_reg :process(clk) -- storage counting data
	begin
		if (rising_edge(clk)) then
			  if((reset='1')or(next_state= stopwatch_display))then --initial
					counter_99_csec_reg <= (others => '0');
					counter_60_sec_reg <= (others => '0');
					counter_60_min_reg <= (others => '0');
					counter_99_hour_reg <= (others => '0');
			  elsif((present_state=counter_start)and(minus_imp='1')) then--freeze mode storage counting data to reg
					counter_99_csec_reg <= counter_99_csec;
					counter_60_sec_reg <= counter_60_sec;
					counter_60_min_reg <= counter_60_min;
					counter_99_hour_reg <= counter_99_hour;
			  else
					counter_99_csec_reg <= counter_99_csec_reg;
					counter_60_sec_reg <= counter_60_sec_reg;
					counter_60_min_reg <= counter_60_min_reg;
					counter_99_hour_reg <= counter_99_hour_reg;
			  end if;
		end if;
	end process counter_reg;


    centise_secound_counter : process(clk_to_100hz) -- centise_secound_counter
    begin
    if (rising_edge(clk_to_100hz)) then
        if((reset='1')or(next_state= stopwatch_display))then --initial
            counter_99_csec<= (others => '0');
        elsif((next_state = counter_start)or(next_state = freeze_display)or(next_state = time_display)) then --counting state or freezing state
            if (counter_99_csec = "10011001")then --99
                counter_99_csec<= (others => '0');
            elsif(counter_99_csec(3 downto 0) = "1001") then
                counter_99_csec(7 downto 4) <= counter_99_csec(7 downto 4)+'1';
                counter_99_csec(3 downto 0) <= "0000";
            else
                counter_99_csec(3 downto 0) <= counter_99_csec(3 downto 0)+'1';
            end if;
        end if;
    end if;
    end process centise_secound_counter;

	secound_counter : process(clk_to_100hz) --: second_counter
    begin
    if (rising_edge(clk_to_100hz)) then
        if((reset='1')or(next_state= stopwatch_display))then --initial
          counter_60_sec<= (others => '0');
        else
            if(csec_co ='1')then
                if (counter_60_sec = "01011001")then --59
                    counter_60_sec<= (others => '0');
                elsif(counter_60_sec(3 downto 0) = "1001") then
                    counter_60_sec(7 downto 4) <= counter_60_sec(7 downto 4)+'1';
                    counter_60_sec(3 downto 0) <= "0000";
                else
                    counter_60_sec(3 downto 0) <= counter_60_sec(3 downto 0)+'1';
                end if;
            end if;
        end if;
    end if;
	end process;

	min_counter : process(clk_to_100hz) --: min_counter
    begin
    if (rising_edge(clk_to_100hz)) then
        if((reset='1')or(next_state= stopwatch_display))then --initial
            counter_60_min<= (others => '0');
        else
            if(sec_co='1') then
                if(counter_60_min = "01011001")then --59
                    counter_60_min<= (others => '0');
                elsif(counter_60_min(3 downto 0) = "1001") then
                    counter_60_min(7 downto 4) <= counter_60_min(7 downto 4)+'1';
                    counter_60_min(3 downto 0) <= "0000";
                else
                    counter_60_min(3 downto 0) <= counter_60_min(3 downto 0)+'1';
                end if;
            end if;
        end if;
    end if;
	end process;


	hour_counter : process(clk_to_100hz) --: hour_counter
    begin
    if (rising_edge(clk_to_100hz)) then
        if((reset='1')or(next_state= stopwatch_display))then --initial
            counter_99_hour<= (others => '0');
        else
            if(min_co='1') then
                if (counter_99_hour = "10011001")then --99
                    counter_99_hour<= (others => '0');
                elsif(counter_99_hour(3 downto 0) = "1001") then
                    counter_99_hour(7 downto 4) <= counter_99_hour(7 downto 4)+'1';
                    counter_99_hour(3 downto 0) <= "0000";
                else
                    counter_99_hour(3 downto 0) <= counter_99_hour(3 downto 0)+'1';
                end if;
            end if;
        end if;
    end if;
	end process;

	carry_out_flag :process(clk)
	begin
		if (rising_edge(clk)) then
			if((reset='1')or(next_state= stopwatch_display))then --initial
				csec_co <='0';
				sec_co <='0';
				min_co <='0';
			else
				if (counter_99_csec = "10011001")then --99
					csec_co <= '1';
				else
					csec_co <= '0';
				end if;
				if ((counter_60_sec = "01011001")and(counter_99_csec = "10011001"))then --59
					sec_co <= '1';
				else
					sec_co <= '0';
				end if;
				if ((counter_60_min = "01011001")and(counter_60_sec = "01011001")and(counter_99_csec = "10011001"))then --59
				min_co <= '1';
				else
				min_co <= '0';
				end if;
			end if;
		end if;
	end process;

    state_clk: process(clk)
    begin
			 if(rising_edge(clk)) then --timing delay another one cycle
				  if(reset='1')then
						present_state <= initial_state;
				  else
						present_state <= next_state;
				  end if;
			 end if;
    end process state_clk;

	crl_dis_signal:process(clk)
    begin
		 if(rising_edge(clk)) then
			 if(reset='1')then
				freeze_lap_reg  <= '0';
			 else
					if(next_state=freeze_display)then
						freeze_lap_reg <= '1';--COUMTER COUNT ON freeze
					elsif ((next_state = stopwatch_display)or(next_state=counter_start))then
						freeze_lap_reg  <= '0';
					else
						freeze_lap_reg <= freeze_lap_reg;
					end if;
			 end if;
		 end if;
    end process crl_dis_signal;


    FSM:process(present_state,action_imp,mode_imp,minus_imp,plus_minus,plus_imp,mode_sw,reset)
    begin
		if(reset='1')then
				next_state<=initial_state;
		  else
			if (mode_sw = '1') then
			    case present_state is
					when initial_state =>
					    if (plus_minus = '1')then
							  next_state <= stopwatch_display;
						 else
							  next_state <= present_state;
						 end if;
					when stopwatch_display =>
						 if(action_imp='1')then
							  next_state <= counter_start;
						 else
							  next_state <= present_state;
						 end if;
					when counter_start =>
						 if(action_imp='1')then
							  next_state <= counter_stop;
						 elsif(minus_imp='1')then
							  next_state <= freeze_display;
						 elsif(mode_imp='1')then
								next_state <= time_display;
						 elsif(plus_imp ='1')then
							  next_state <= stopwatch_display;
						 else
							  next_state <= present_state;
						 end if;
					when counter_stop =>
						 if(action_imp='1')then
							  next_state <= counter_start;
						 elsif(plus_imp='1')then
							  next_state <= stopwatch_display;
						 else
							  next_state <= present_state;
						 end if;
					when freeze_display =>
						 if (minus_imp='1')then
							  next_state <= counter_start;
						 elsif(plus_imp='1')then
							  next_state <= stopwatch_display;
						 else
							  next_state <= present_state;
						 end if;
					when time_display =>
						 if(plus_minus = '1')then
							  next_state <= counter_start;
						 else
							  next_state <= present_state;
						 end if;
					when others =>
						next_state <= present_state;
			  end case;
			 else
				next_state <= present_state;
			end if;
	    end if;
    end process FSM;

end Behavioral;
