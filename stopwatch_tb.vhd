--------------------------------------------------------------------------------
-- Company: 
-- Engineer:
--
-- Create Date:   14:44:28 07/10/2019
-- Design Name:   
-- Module Name:   /nas/ei/home/ge73gej/Desktop/stopwatch/test/stopwatch_tb.vhd
-- Project Name:  test
-- Target Device:  
-- Tool versions:  
-- Description:   
-- 
-- VHDL Test Bench Created by ISE for module: stop_watch
-- 
-- Dependencies:
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
--
-- Notes: 
-- This testbench has been automatically generated using types std_logic and
-- std_logic_vector for the ports of the unit under test.  Xilinx recommends
-- that these types always be used for the top-level I/O of a design in order
-- to guarantee that the testbench will bind correctly to the post-implementation 
-- simulation model.
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
 
-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--USE ieee.numeric_std.ALL;
 
ENTITY stopwatch_tb IS
END stopwatch_tb;
 
ARCHITECTURE behavior OF stopwatch_tb IS 
 
    -- Component Declaration for the Unit Under Test (UUT)
 
    COMPONENT stop_watch
    PORT(
         clk_to_100hz : IN  std_logic;
         clk : IN  std_logic;
         reset : IN  std_logic;
         mode_sw : IN  std_logic;
         action_imp : IN  std_logic;
         mode_imp : IN  std_logic;
         minus_imp : IN  std_logic;
         plus_imp : IN  std_logic;
         plus_minus : IN  std_logic;
         csec_count : OUT  std_logic_vector(7 downto 0);
         sec_count : OUT  std_logic_vector(7 downto 0);
         min_count : OUT  std_logic_vector(7 downto 0);
         hour_count : OUT  std_logic_vector(7 downto 0);
         freeze_lap : OUT  std_logic
        );
    END COMPONENT;
    

   --Inputs
   signal clk_to_100hz : std_logic := '0';
   signal clk : std_logic := '0';
   signal reset : std_logic := '0';
   signal mode_sw : std_logic := '0';
   signal action_imp : std_logic := '0';
   signal mode_imp : std_logic := '0';
   signal minus_imp : std_logic := '0';
   signal plus_imp : std_logic := '0';
   signal plus_minus : std_logic := '0';

 	--Outputs
   signal csec_count : std_logic_vector(7 downto 0);
   signal sec_count : std_logic_vector(7 downto 0);
   signal min_count : std_logic_vector(7 downto 0);
   signal hour_count : std_logic_vector(7 downto 0);
   signal freeze_lap : std_logic;

   -- Clock period definitions
   constant clk_to_100hz_period : time := 10 ms;
   constant clk_period : time := 10ms;
 
BEGIN
 
	-- Instantiate the Unit Under Test (UUT)
   uut: stop_watch PORT MAP (
          clk_to_100hz => clk_to_100hz,
          clk => clk,
          reset => reset,
          mode_sw => mode_sw,
          action_imp => action_imp,
          mode_imp => mode_imp,
          minus_imp => minus_imp,
          plus_imp => plus_imp,
          plus_minus => plus_minus,
          csec_count => csec_count,
          sec_count => sec_count,
          min_count => min_count,
          hour_count => hour_count,
          freeze_lap => freeze_lap
        );

   -- Clock process definitions
   clk_to_100hz_process :process
   begin
		clk_to_100hz <= '0';
		wait for clk_to_100hz_period/2;
		clk_to_100hz <= '1';
		wait for clk_to_100hz_period/2;
   end process;
 
   clk_process :process
   begin
		clk <= '0';
		wait for clk_period/2;
		clk <= '1';
		wait for clk_period/2;
   end process;
 

   -- Stimulus process
   -- Stimulus process
   stim_proc: process
	begin
		wait for 10ms;	
		mode_sw <= '1';
      --wait for clk_to_100hz_period*10;

      -- insert stimulus here 
		
----test into stop watch display
--		wait for 10ms;
--		plus_minus	<= '1'; -- into stop watch display
--		wait for 10ms;
--		plus_minus	<= '0';
--
--		wait for 10ms;
--		reset	<= '1';	--reset
--		wait for 10ms;
--		reset	<= '0';
----test into counter start mode
--		wait for 10ms;
--		plus_minus	<= '1';	-- into stop watch display
--		wait for 10ms;
--		plus_minus	<= '0';
--
--		wait for 10ms;
--		action_imp	<= '1';	-- into counter start mode
--		wait for 10ms;
--		action_imp	<= '0';
--
--		wait for 10ms;
--
--		wait for 10ms;
--		plus_imp	<= '1';	-- back to stop watch display
--		wait for 10ms;
--		plus_imp	<= '0';
--
--		wait for 10ms;
--		action_imp	<= '1';	-- into counter start mode
--		wait for 10ms;
--		action_imp	<= '0';
--
--		wait for 10ms;
--
--		wait for 10ms;
--		reset	<= '1';	--reset
--		wait for 10ms;
--		reset	<= '0';
--
---- test when counting back to time display mode
--		
--		wait for 10ms;
--		plus_minus	<= '1';	-- into stop watch display
--		wait for 10ms;
--		plus_minus	<= '0';
--
--		wait for 10ms;
--		action_imp	<= '1';	-- into counter start mode
--		wait for 10ms;
--		action_imp	<= '0';
--
--		wait for 10ms;
--
--		wait for 10ms;
--		mode_imp	<= '1';	-- into display mode
--		wait for 10ms;
--		mode_imp	<= '0';
--
--		wait for 10ms;
--		plus_minus	<= '1';	-- into stop watch display
--		wait for 10ms;
--		plus_minus	<= '0';
--
--		wait for 10ms;
--
--		wait for 10ms;
--		mode_imp	<= '1';	-- into display mode
--		wait for 10ms;
--		mode_imp	<= '0';
--
--		wait for 10ms;
--		reset	<= '1';	--reset
--		wait for 10ms;
--		reset	<= '0';
--
----test into counter stop mode
--
--		wait for 10ms;
--		plus_minus	<= '1';	-- into stop watch display
--		wait for 10ms;
--		plus_minus	<= '0';
--
--		wait for 10ms;
--		action_imp	<= '1';	-- into counter start mode
--		wait for 10ms;
--		action_imp	<= '0';
--
--		wait for 10ms;
--
--		wait for 10ms;
--		action_imp	<= '1';	-- into counter stop mode
--		wait for 10ms;
--		action_imp	<= '0';
--
--		wait for 10ms;
--
--		wait for 10ms;
--		action_imp	<= '1';	-- back counter start mode
--		wait for 10ms;
--		action_imp	<= '0';
--
--		wait for 10ms;
--
--		wait for 10ms;
--		action_imp	<= '1';	-- into counter stop mode
--		wait for 10ms;
--		action_imp	<= '0';
--
--		wait for 10ms;
--		plus_imp	<= '1';	-- into stop watch display
--		wait for 10ms;
--		plus_imp	<= '0';
--
--		wait for 10ms;
--		action_imp	<= '1';	-- into counter start mode
--		wait for 10ms;
--		action_imp	<= '0';
--
--		wait for 10ms;
--		action_imp	<= '1';	-- into counter stop mode
--		wait for 10ms;
--		action_imp	<= '0';
--
--		wait for 10ms;
--		reset	<= '1';	--reset
--		wait for 10ms;
--		reset	<= '0';	

-- test into stop watch freeze screen

		wait for 10ms;
		plus_minus	<= '1';	-- into stop watch display
		wait for 10ms;
		plus_minus	<= '0';

		wait for 10ms;
		action_imp	<= '1';	-- into counter start mode
		wait for 10ms;
		action_imp	<= '0';

		wait for 10ms;

		wait for 10ms;
		minus_imp	<= '1';	-- into stop watch freeze screen
		wait for 10ms;
		minus_imp	<= '0';

		wait for 10ms;

		wait for 10ms;
		minus_imp	<= '1';-- back to counter start mode
		wait for 10ms;
		minus_imp	<= '0';

		wait for 10ms;

		wait for 10ms;
		minus_imp	<= '1';	-- into stop watch freeze screen
		wait for 10ms;
		minus_imp	<= '0';

		wait for 10ms;
		plus_imp	<= '1';	-- back to stop watch display
		wait for 10ms;
		plus_imp	<= '0';	

		wait for 10ms;

		wait for 10ms;
		action_imp	<= '1';	-- into counter start mode
		wait for 10ms;
		action_imp	<= '0';

		wait for 10ms;

		wait for 10ms;
		minus_imp	<= '1';	-- into stop watch freeze screen
		wait for 10ms;
		minus_imp	<= '0';

		wait for 10ms;
	
		wait for 10ms;
		reset	<= '1';	--reset
		wait for 10ms;
		reset	<= '0';

------------------------------------------------------------------------------------

--hyper test in random buttom
		
		wait for 10ms;
		plus_minus	<= '1';	-- into stop watch display
		wait for 10ms;
		plus_minus	<= '0';

		wait for 10ms;
		action_imp	<= '1';	-- into counter start mode
		wait for 10ms;
		action_imp	<= '0';

		wait for 100ms; --counting 

		wait for 10ms;
		action_imp	<= '1';	-- into counter stop mode
		wait for 10ms;
		action_imp	<= '0';

		wait for 100ms; --counting 

		wait for 10ms;
		plus_minus	<= '1';	-- still in counter stop mode
		wait for 10ms;
		plus_minus	<= '0';

		wait for 10ms;
		mode_imp	<= '1';	-- still in counter stop mode
		wait for 10ms;
		mode_imp	<= '0';

		wait for 10ms;
		action_imp	<= '1';	-- back to counter start mode
		wait for 10ms;
		action_imp	<= '0';

		wait for 100ms; --counting 

		wait for 10ms;
		minus_imp	<= '1';	-- into stop watch freeze screen
		wait for 10ms;
		minus_imp	<= '0';


		wait for 10ms;
		plus_minus	<= '1';	-- still in stop watch freeze screen
		wait for 10ms;
		plus_minus	<= '0';

		wait for 10ms;
		mode_imp	<= '1';	-- still in stop watch freeze screen
		wait for 10ms;
		mode_imp	<= '0';

		wait for 10ms;
		action_imp	<= '1';	-- back to stop watch freeze screen
		wait for 10ms;
		action_imp	<= '0';

		wait for 10ms;
		minus_imp	<= '1';	-- back to counter start mode
		wait for 10ms;
		minus_imp	<= '0';

		wait for 100ms; --counting 

		wait for 10ms;
		mode_imp	<= '1';	-- back to time display counting on back ground
		wait for 10ms;
		mode_imp	<= '0';

		wait for 10ms;
		mode_imp	<= '1';	-- still in time display counting
		wait for 10ms;
		mode_imp	<= '0';

		wait for 10ms;
		action_imp	<= '1';	-- still in time display counting
		wait for 10ms;
		action_imp	<= '0';

		wait for 10ms;
		minus_imp	<= '1';	-- still in time display counting
		wait for 10ms;
		minus_imp	<= '0';

		wait for 10ms;
		plus_imp	<= '1';	-- still in time display counting
		wait for 10ms;
		plus_imp	<= '0';

		wait for 10ms;
		plus_minus	<= '1';	-- back to counter stop
		wait for 10ms;
		plus_minus	<= '0';

		wait for 10ms;
		reset	<= '1';	-- back to counter stop
		wait for 10ms;
		reset	<= '0';
-- test finish

   end process;

END;
