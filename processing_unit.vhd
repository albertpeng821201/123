library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-------------------------------------------------------------------------------
-- the processing unit is instantiated in the sobel_to_system
-- there you can identify the overall architecture as depicted in the manual
-------------------------------------------------------------------------------

entity processing_unit is
  port (bus_clk : in  std_logic;
        rst     : in  std_logic;
        enable  : in  std_logic;
        GPIO    : in  std_logic_vector (7 downto 0);
        din_0   : in  std_logic_vector (7 downto 0);
        din_1   : in  std_logic_vector (7 downto 0);
        din_2   : in  std_logic_vector (7 downto 0);
        o_data  : out std_logic_vector (7 downto 0);
        o_wr_en : out std_logic;
        p_data  : out std_logic_vector (31 downto 0);
        p_wr_en : out std_logic;
        p_full  : in  std_logic);
end processing_unit;

-------------------------------------------------------------------------------
architecture behavioral of processing_unit is

  -- the size of the frames to be processed
  constant FRAME_HEIGHT : integer := 480;
  constant FRAME_WIDTH  : integer := 854;

  -- registers to store the 3x3 matrix
  signal d_00, d_01, d_02 : unsigned (9 downto 0);
  signal d_10, d_11, d_12 : unsigned (9 downto 0);
  signal d_20, d_21, d_22 : unsigned (9 downto 0);

  -- the directional gradients
  -- should be used in a way that the values are stored in registers 
  signal Gx, Gy : unsigned (9 downto 0);

  -- intermediate signals for calculation
  -- if needed you can add more signals or remove unused signals
  signal sobel_x0, sobel_x2, sobel_y0, sobel_y2 : unsigned (9 downto 0);
  signal sobel_xt, sobel_yt                     : unsigned (9 downto 0);

  -- we use internally the square of the threshold to avoid square root calculation
  -- signal is fed by GPIO
  signal threshold_square : unsigned (15 downto 0);

  -- intermediate output data value stored in register
  signal o_data_reg : std_logic_vector(7 downto 0);

  -- counters for row and coulmn within frame
  signal col_count : unsigned (9 downto 0);
  signal row_count : unsigned (8 downto 0);

  -- counters and registers for hardware profiler
  signal frame_count, frame_cycles : unsigned (31 downto 0);
  signal frame_t, frame            : std_logic_vector (31 downto 0);

  signal res_int : std_logic;
  signal flag    : std_logic;
  
begin

-------------------------------------------------------------------------------
-- Store the data in registers for processing
--
-- d0?, d1?, d2? are shift registers to receive the data from the respective input
-- and move it to the next stage for each clock if the enable input is '1'
-- d0? corresponds to a, b and c from the description in the manual, d1? to d, e, f etc.
--
-------------------------------------------------------------------------------

  input_regs : process (bus_clk)
  begin
    if (bus_clk'event and bus_clk = '1') then
      if (res_int = '1') then
        d_00 <= (others => '0'); d_01 <= (others => '0'); d_02 <= (others => '0');
        d_10 <= (others => '0'); d_11 <= (others => '0'); d_12 <= (others => '0');
        d_20 <= (others => '0'); d_21 <= (others => '0'); d_22 <= (others => '0');
      elsif(enable = '1') then
        d_00 <= "00"&unsigned(din_0); d_01 <= d_00; d_02 <= d_01;
        d_10 <= "00"&unsigned(din_1); d_11 <= d_10; d_12 <= d_11;
        d_20 <= "00"&unsigned(din_2); d_21 <= d_20; d_22 <= d_21;
      end if;
    end if;
  end process input_regs;

-------------------------------------------------------------------------------
-- Do the actual sobel processing
-- Calculate the horizontal and vertical gradients
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--
-- here you should calculate Gx and Gy from the manual and take care that these values are 
-- also stored in registers if the enable input enable is '1'
-- Otherwise when not registering an intermediate value of the processing, the logical path
-- from the input registers to the output FIFO will be too long for the target clock frequency
--
-- The signals sobel_x?, sobel_y? are intended to be used for intermediate calculations
-- before assigning the result to Gx and Gy.
-- If you require more intermediate signals you have to declare them appropriately in the 
-- declaration section of the architecture
--
-- Note that Gx and Gy are of type unsigned. Therefore, make sure that Gx and Gy are in any
-- case positive values (they have to be squared anyway to determine the overall gradient G).
--
-- Make sure to not forget the division by 8 to get Gx and Gy. Maybe you can use some construct
-- from the introduction to VHDL...
-------------------------------------------------------------------------------

-- 
-- WRITE YOUR CODE HERE
--




-------------------------------------------------------------------------------
-- Calculate the overall gradient and the actual output value
-- for the middle pixel of the 3x3 matrix
-------------------------------------------------------------------------------
--
-- From the declaration of threshold_square you have seen that we are working not with 
-- the threshold to avoid the square root operation. Be sure to consider this in 
-- your code.
--
-- Note also that sobel edge detection is only done if GPIO(0) is '1'; otherwise o_data_reg should 
-- be assigned the approppriate unprocessed pixel value
--
-- To cope with edges, o_data_reg should get the value "10000000" (128, gray) if the following condition
-- applies:
-- (row_count = 0 AND col_count >= 5) OR (row_count = 1) OR (row_count = 2 AND col_count <= 2) 
-- OR (col_count = 3) OR (col_count = 4)
-- the reason for these values come from the latency introduced by the pipleine stages 
-- and row and column counters count position of arriving pixels.
--
-- Here no more registers should be generated, so do not use clocked processes.
-- Do not forget to have all read signals in the sensitivity list of unclocked processes...
--
-------------------------------------------------------------------------------

-- 
-- WRITE YOUR CODE HERE
--




-------------------------------------------------------------------------------
-- Registered output to avoid long paths
-------------------------------------------------------------------------------

  output_regs : process (bus_clk)
  begin
    if (bus_clk'event and bus_clk = '1') then
      if (res_int = '1') then
        o_data <= (others => '0');
      elsif(enable = '1') then
        o_data <= o_data_reg;
      end if;
    end if;
  end process output_regs;

-------------------------------------------------------------------------------
-- Counters for counting columns and rows of the frame
-------------------------------------------------------------------------------

  row_column_cntr : process (bus_clk)
  begin
    if (bus_clk'event and bus_clk = '1') then
      if (res_int = '1') then
        col_count   <= to_unsigned(FRAME_WIDTH-1, 10);
        row_count   <= to_unsigned(FRAME_HEIGHT-1, 9);
        frame_count <= (others => '0');
      elsif(enable = '1') then
        if(col_count = FRAME_WIDTH -1) then
          col_count <= (others => '0');
          if(row_count = FRAME_HEIGHT -1) then
            row_count <= (others => '0');
            if(flag = '1') then
              frame_count <= frame_count +1;
            end if;
          else
            row_count <= row_count + 1;
          end if;
        else
          col_count <= col_count + 1;
        end if;
      end if;
    end if;
  end process row_column_cntr;

-------------------------------------------------------------------------------
-- Set the threshold
-------------------------------------------------------------------------------

  threshold : process (GPIO(2 downto 1))
  begin
    case GPIO(2 downto 1) is
      when "00" =>
        threshold_square <= to_unsigned(64, 16);
      when "01" =>
        threshold_square <= to_unsigned(100, 16);
      when "10" =>
        threshold_square <= to_unsigned(400, 16);
      when others =>
        threshold_square <= to_unsigned(900, 16);
    end case;
  end process threshold;

-------------------------------------------------------------------------------
-- Generate write enable for output FIFO
-------------------------------------------------------------------------------

-- o_wr_en has to be the enable signal but delayed by enough cycles of col_count and row_count to fill pipeline

  enable_output : process (bus_clk)
  begin
    if (bus_clk'event and bus_clk = '1') then
      if (res_int = '1') then
        flag <= '0';
      elsif (col_count = 4 and row_count = 1) then
        flag <= '1';
      end if;
    end if;
  end process enable_output;

  o_wr_en <= enable and flag;

-------------------------------------------------------------------------------
-- Generate internal reset signal: reset either via system reset rst or GPIO(7)
-------------------------------------------------------------------------------
  res_int <= rst or GPIO(7);

-------------------------------------------------------------------------------
-- Hardware Profiler
-------------------------------------------------------------------------------
-- 
-- The number of clock cycles per frame are counted and output to the debug FIFO
-- that can be read from the processor

-- X"3c3c3c3c" and X"3e3e3e3e" are used as delimiting patterns at the beginning
-- and the end of each data set, which consists else of the duration of the frame
-- and the associated frame number.
-- When a frame is over, the values are intermediately registered and the delimiters 
-- and the data are output in four subsequent clock cycles
--
-------------------------------------------------------------------------------

  hw_profiler : process(bus_clk)
    type phase is (do_nothing, out_sig1, out_time, out_frame, out_sig2);
    variable phase_v : phase;
  begin
    if (bus_clk'event and bus_clk = '1') then
      if(res_int = '1') then
        frame_cycles <= (others => '0');
        phase_v      := do_nothing;
        p_wr_en      <= '0';
        p_data       <= (others => '0');
      else
        if(p_full = '0') then
          -- output the measured number of clock cycles required for one frame
          if(phase_v = out_sig1) then
            p_data  <= X"3c3c3c3c";
            p_wr_en <= '1';
            phase_v := out_time;
          elsif(phase_v = out_time) then
            p_data  <= frame_t;
            p_wr_en <= '1';
            phase_v := out_frame;
          elsif(phase_v = out_frame) then
            p_data  <= frame;
            p_wr_en <= '1';
            phase_v := out_sig2;
          elsif(phase_v = out_sig2) then
            p_data  <= X"3e3e3e3e";
            p_wr_en <= '1';
            phase_v := do_nothing;
          else
            p_wr_en <= '0';
            phase_v := do_nothing;
          end if;
        else
          p_wr_en <= '0';
          phase_v := do_nothing;
        end if;

        -- count number of clock cycles per frame. If frame is over, output frame time and frame number
        if((col_count = FRAME_WIDTH -1) and (row_count = FRAME_HEIGHT -1) and (flag = '1'))then
          frame_t      <= std_logic_vector(frame_cycles);
          frame        <= std_logic_vector(frame_count);
          frame_cycles <= (others => '0');
          phase_v      := out_sig1;
        else
          frame_cycles <= frame_cycles + 1;
        end if;
      end if;
    end if;
  end process hw_profiler;

end behavioral;

