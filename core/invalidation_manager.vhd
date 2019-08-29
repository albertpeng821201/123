use STD.textio.all;
library ieee;
use ieee.std_logic_1164.all;
USE ieee.numeric_std.ALL;
use ieee.std_logic_textio.all;
library grlib;
use grlib.amba.all;
use grlib.stdlib.all;
use grlib.devices.all;
use grlib.dma2ahb_package.all;
library techmap;
use techmap.gencomp.all;
library top;
use top.config.all;
library icrm;
use icrm.crm_pkg.all;
library ina;
library ina_pkg;
use ina_pkg.ina_config.all;
use ina_pkg.bus_package.all;

entity invalidation_manager is
	generic(
		hindex      : integer := 0;
		hirq        : integer := 0;
		venid       : integer := VENDOR_GAISLER;
		devid       : integer := 0;
		version     : integer := 0;
		tech        : integer := DEFMEMTECH;
		incaddr     : integer := 0;
		dir_mode    : integer := 1; -- 1:cacheless directory 2:cache-based directory
		my_tile_id  : integer := 0;
		x_loc       : integer := 0;
		y_loc       : integer := 0;
		ioaddr      : integer := 16#80D#
	);    -- maximum number of tiles in one coherency region

	port(
		rst               : in  std_ulogic;
		clk               : in  std_ulogic;
		ahbmi             : in  ahb_mst_in_type;
		ahbmo             : out ahb_mst_out_type;
		CStoIM            : in CStoIM_type;
		counters		  : out invManCnt_type;
		evictionPolicy	  : in std_logic_vector(31 downto 0);
		rd_en             : out std_ulogic;
		empty             : in std_ulogic;
		almost_full       : in std_ulogic;
		r_addr            : in  std_logic_vector((abit - 1) downto 0);
		r_data_rd         : out std_logic_vector((dbit -1) downto 0); --two additional bits are status bits
		r_data_wr         : in std_logic_vector((dbit -1) downto 0); --two additional bits are status bits
		r_enable          : in std_logic;
		r_write           : in std_logic;
		r_req             : in std_logic;
		r_gnt             : out std_logic;
		r_addr_snoop      : in  std_logic_vector((abit - 1) downto 0);
		r_data_rd_snoop   : out std_logic_vector((dbit -1) downto 0); --two additional bits are status bits
		r_data_wr_snoop   : in std_logic_vector((dbit -1) downto 0); --two additional bits are status bits
		r_enable_snoop    : in std_logic;
		r_write_snoop     : in std_logic;
		r_req_snoop       : in std_logic;
		r_gnt_snoop       : out std_logic;
		im_to_chipscope   : out crm_im_chipscope_type
	);
end;

architecture rtl of invalidation_manager is

signal dmai : DMA_In_Type := DMA_In_Type_none;
signal dmao: DMA_OUt_Type;
signal CStoIM_sig : CStoIM_type := ((others => '0'),(others => '0'),(others => '0'));
type state_type is (idle, fifo_read, select_action, invalidation_generation, copy_sharing_vector, invalidate_l2, invalidate_l1, update_sharing_vector, force_write_through, update_sharing_table, crmLUT_config);
signal current_s,next_s: state_type;
signal r,t : invMan_type := invMan_type_default;
signal rc,tc : invManCnt_type := invManCnt_type_default;

----------------ram signal--------------
signal ram_addr		:  std_logic_vector((abit - 1) downto 0);
signal ram_data_rd	:  std_logic_vector((dbit - 1) downto 0); --two additional bits are status bits
signal ram_data_wr	:  std_logic_vector((dbit - 1) downto 0); --two additional bits are status bits
signal ram_enable, ram_write, ram_data_valid : std_logic := '0';
signal req, gnt: std_logic := '0';
--signal dir_busy: std_logic := '0';
signal evict_flag : std_logic := '0';
signal evict_data :  std_logic_vector((dbit - 1) downto 0);
signal evict_address : std_logic_vector((abit-1) downto 0);
signal rd_data_change : std_logic := '0';
signal protect_set : std_logic := '0';
signal evictionPolicy_int : integer := 0;	-- 1: least number of sharers eviction, -- 2: least recently used eviction, -- 3: shortest distance first -- 4: hybrid eviction policy -- 5: dummy eviction of way 0
-------------------------------------------

function addr_trans(
	tile_id     : integer) return std_logic_vector is
	variable ret: std_logic_vector(7 downto 0);
	begin

	ret :=  "0100" & std_logic_vector(to_unsigned(tile_id,4));
	return ret;
end function addr_trans;

---------------------------------Invalidation tile identifier-----------------------------------------------
impure function inv_tile_identifier(
	tiles_inv   : std_logic_vector(r.crmLUT'high downto 0)) return ret_type is

	variable ret: ret_type;
	begin

	ret.tile_id := 0;
	ret.new_inv_tiles := tiles_inv;
	for i in 0 to r.crmLUT'high loop
		if(tiles_inv(i) = '1') then
			ret.tile_id := r.crmLUT(i);
			ret.new_inv_tiles(i) := '0';
			return ret;
		end if;
	end loop;
	return ret;
end function inv_tile_identifier;

---------------------------------CRM LUT Config--------------------------------------------------------------
function crmLUT_config_func(
	sharing_tiles : std_logic_vector((dim_x*dim_y)-1 downto 0)) return crmLUT_type is
	variable crmLUT : crmLUT_type;
	variable cnt    : integer := 0;
	begin

	for i in 0 to sharing_tiles'high loop
		if(sharing_tiles(i) = '1') then
			crmLUT(cnt) := i;
			cnt := cnt + 1;
		end if;
	end loop;
	return crmLUT;
end function crmLUT_config_func;
---------------------------------dir_update function---------------------------------------------------------
impure function dir_update(
	ram_data_rd : std_logic_vector((dbit - 1) downto 0);
	tile_src    : integer) return std_logic_vector is

	variable new_ram_data   : std_logic_vector((region_size - 2) downto 0);
	variable status_bits    : std_logic_vector(1 downto 0) := (others => '0');
	begin

	if(ram_data_rd(region_size) = '0' and ram_data_rd(region_size-1) = '1') then  -- handle memory corrupted by alien tile
		new_ram_data := (others => '0');
		status_bits(1) := '0';
		status_bits(0) := '1';
		return "01"&zeros_32(new_ram_data'high downto new_ram_data'low);
	elsif(ram_data_rd(region_size) /= '1') then -- first time read transaction fresh directory entery "XXXXXXXXX"
		new_ram_data := (others => '0');
		status_bits(1) := '1';
		status_bits(0) := '0';
	else    -- Normal directory entry
		new_ram_data := ram_data_rd((region_size - 2) downto 0);
		status_bits := ram_data_rd(ram_data_rd'high downto (region_size-1));   -- data pattern <enable bit><exceed max tiles in cr><tiles logical>
	end if;

	for i in 0 to r.crmLUT'high loop
		if(r.crmLUT(i) = tile_src) then
			new_ram_data(i) := '1';
			return status_bits & new_ram_data;
		end if;
	end loop;

	return status_bits(1) & '1' & new_ram_data;     -- Did not find tile_src in crmLUT => must be an alien tile
end function dir_update;

-----------------------------Inv inv_dir_update ---------------------------------
impure function inv_dir_update(
    ram_data_rd : std_logic_vector((dbit - 1) downto 0);
    tile_src    : integer) return std_logic_vector is

	variable new_ram_data : std_logic_vector((region_size - 2) downto 0);
    variable status_bits : std_logic_vector(1 downto 0) := (others => '0');
    variable cnt : integer := 0;
	begin

    new_ram_data := (others => '0');
	if(ram_data_rd(region_size) = '0' and ram_data_rd(region_size-1) = '1') then
		return "01"&zeros_32((region_size -2) downto 0);
	elsif(ram_data_rd(region_size) /= '1') then	--data pattern <enable bit><exceed max tiles in cr><tiles logical>
        status_bits(1) := '1';
        status_bits(0) := '0';
    else
		status_bits := ram_data_rd(ram_data_rd'high downto (region_size-1));
    end if;

    if(tile_src = my_tile_id) then -- when writtern by local tile
        return status_bits & new_ram_data;
    else -- when writtern by tiles within coherency region
		for i in 0 to r.crmLUT'high loop
			if(r.crmLUT(i) = tile_src) then
                new_ram_data(i) := ram_data_rd(i);
                return status_bits & new_ram_data;
            end if;
        end loop;
		return "01" & new_ram_data;	-- when written by alien tile
    end if;

    return status_bits & new_ram_data;
end function inv_dir_update;

--------------------------inv_tile_update function-------------------- Which Tiles to Invalidate
impure function inv_tile_update(
	ram_data_rd : std_logic_vector((dbit - 1) downto 0);
	tile_src    : integer) return std_logic_vector is

	variable ret, ret_all : std_logic_vector((region_size -2) downto 0);
	variable ram_data : std_logic_vector((region_size - 2) downto 0);
    begin

    ret_all := (others => '1');
    ret := (others => '0');
    ram_data := ram_data_rd (ram_data'high downto 0);

	if (ram_data_rd(region_size) = '0' and ram_data_rd(region_size-1) = '1') then
        return ret;
	elsif ram_data_rd(region_size) /= '1' then -- check whether the directory entry is valid
        return ret;
	elsif ram_data_rd(region_size-1) = '1' then -- check whether sharers exceed the max tiles in CR
        return ret_all;
    end if;

	for i in 0 to r.crmLUT'high loop
		if(r.crmLUT(i) = tile_src) then
			ret(i) := '0';	-- do not send INV to the tile who issued the write
		else
			ret(i) := ram_data_rd(i);
		end if;
    end loop;
    return ret;
end function inv_tile_update;

begin

CStoIM_sig <= CStoIM;
counters <= rc;
dmai <= r.dmai;
evictionPolicy_int <= to_integer(unsigned(evictionPolicy));

crm_ahbmst : entity grlib.dma2ahb
	generic map(
		hindex => hindex,
		syncrst	=> 1,
		boundary =>	1
		)
	port map(
		-- AMBA AHB system signals
		HCLK => clk,
		HRESETn => rst,

		-- Direct Memory Access Interface
		DMAIn => dmai,
		DMAOut => dmao,

		-- AMBA AHB Master Interface
		AHBIn => ahbmi,
		AHBOut => ahbmo
		);

im_to_chipscope.im_dmao <= dmao;
im_to_chipscope.im_dmai <= dmai;

im_to_chipscope.im_IdleTrans <= r.busAccess.IdleTrans;
im_to_chipscope.im_busAccess_done <= r.busAccess.done;

im_to_chipscope.im_sharingVector <= r.sharingVector;

im_to_chipscope.im_ram_addr <= ram_addr;
im_to_chipscope.im_ram_data_rd <= ram_data_rd;
im_to_chipscope.im_ram_data_wr <= ram_data_wr;
im_to_chipscope.im_ram_write <= ram_write;
im_to_chipscope.im_ram_enable <= ram_enable;

clkProcess : process(clk,rst)
begin
	if(rst /= '1') then
		current_s <= idle;
	elsif(clk='1' and clk'Event) then
		current_s <= next_s;
		r <= t;
		rc <= tc;
	end if;
end process clkProcess;

mainProcess : process(current_s, CStoIM_sig, dmao, empty, gnt, ram_data_rd, r, rc, rd_data_change, evict_data, evict_address, evict_flag)
variable v	: invMan_type;
variable vc : invManCnt_type;
variable address, data : std_logic_vector(31 downto 0);

begin
	next_s <= current_s;

	address := (others => '0');
	data := (others => '0');
	v := r;
	vc := rc;

	-- FIFO Signals
	rd_en <= '0';

	-- RAM Signals
	req <= '0';
	ram_enable <= '0';
	ram_write  <= '0';
	protect_set <= '0';
	ram_addr <= (others => '0');
	ram_data_wr <= (others => '0');

	case current_s is
		when idle =>
			if(empty = '0') then
				next_s <= fifo_read;
			else
				next_s <= idle;
			end if;
			im_to_chipscope.im_current_s <= x"0";

		when fifo_read =>
			req <= '1';
			rd_en <= '1';
			
			next_s <= select_action;
			im_to_chipscope.im_current_s <= x"1";

		when select_action =>
			if (CStoIM_sig.address(3 downto 0) = "0001") or (CStoIM_sig.address(3 downto 0) = "0010") then
				req <= '1';
				ram_enable <= '1';
				ram_addr <= CStoIM_sig.address((ram_addr'high + 5) downto 5);
				v.rd_data_change := rd_data_change;
				if(gnt = '1') then
					case(CStoIM_sig.address(3 downto 0)) is
						when "0001" => next_s <= copy_sharing_vector; -- Invalidation generation -> Write to remote CRM (which then performs Invalidation execution), Uses Bus Master
									   protect_set <= '1';
						when "0010" => next_s <= update_sharing_table; -- Update Sharing Table    -> Internally update the ST, Does not use Bus Master
						when others => next_s <= idle;
					end case;
				end if;
			else
				case(CStoIM_sig.address(3 downto 0)) is
					when "0000" => next_s <= invalidate_l2; -- Invalidation execution  -> Invalidates L2 (via L2FlushReg) + Invalidates L1 (via dummy writes), Uses Bus Master
					when "0011" => next_s <= force_write_through; -- Write back transaction  -> L2 WB (via L2FlushReg), Uses the Bus Master
					when "0100" => next_s <= crmLUT_config; -- Configure crmLUT (doesn't need the gnt, but kept in for modularity)
					when others => next_s <= idle;
				end case;
			end if;
			im_to_chipscope.im_current_s <= x"2";

		when crmLUT_config =>
			v.crmLUT := crmLUT_config_func(CStoIM_sig.data);

			next_s <= idle;
			im_to_chipscope.im_current_s <= x"3";

-- Invalidation Generation (Start)
		when copy_sharing_vector =>	-- Copy read data to sharingVector; Update Sharing Vector in RAM to reflect Writer's TileSrc
			req <= '1';
			ram_enable <= '1';	-- Keep consecutive request hot on the ram's inputs
			ram_write <= '1';
			protect_set <= '1';
			ram_addr <= CStoIM_sig.address((ram_addr'high + 5) downto 5);
			ram_data_wr <= inv_dir_update(ram_data_rd, to_integer(unsigned(CStoIM_sig.tile_src)));
			v.sharingVector := inv_tile_update(ram_data_rd, to_integer(unsigned(CStoIM_sig.tile_src)));

			if r.rd_data_change /= rd_data_change then	-- True when memory is done with read request initiated at "select action"
				if(v.sharingVector(r.crmLUT'high downto 0) = zeros_32(r.crmLUT'high downto 0)) then
					next_s <= idle;
				else
					next_s <= invalidation_generation;
				end if;
			end if;
			im_to_chipscope.im_current_s <= x"4";

		when invalidation_generation =>		--Send Invalidation based on the Sharing Vector
			address := addr_trans(inv_tile_identifier(r.sharingVector(r.crmLUT'high downto 0)).tile_id) & std_logic_vector(to_unsigned(ioaddr, 4)) & x"00020"; -- (Akshay 08Dec17) Parameterized the IOADDR for the CRM. Currently its at x"D"
			if r.evict_flag = '0' then
				data := addr_trans(my_tile_id) & CStoIM_sig.address(23 downto 0);
			else -- In case the state was reached because of an Invalidation due to Eviction
				data := addr_trans(my_tile_id) & zeros_32((zeros_32'high-8-abit-5) downto 0) & r.evict_address & zeros_32(4 downto 0);
			end if;
			BUS_WRITE_SINGLE(address, data, dmao, v.dmai, r.busAccess, v.busAccess);

			if(v.busAccess.done = '1') then
				vc.invGen_cnt := rc.invGen_cnt + '1';
				next_s <= update_sharing_vector;
			else
				next_s <= invalidation_generation;
			end if;

			im_to_chipscope.im_current_s <= x"5";

		when update_sharing_vector =>	--Update copied Sharing Vector to reflect remaining tiles to be invalidated
			v.sharingVector := inv_tile_identifier(r.sharingVector(r.crmLUT'high downto 0)).new_inv_tiles;

			if(v.sharingVector(r.crmLUT'high downto 0) = zeros_32(r.crmLUT'high downto 0)) then
				v.evict_flag := '0'; -- In case the state was reached because of an Invalidation due to Eviction
				next_s <= idle;
			else
				next_s <= invalidation_generation;
			end if;
			im_to_chipscope.im_current_s <= x"6";
-- Invalidation Generation (End)

-- Invalidation Execution (Start)
		when invalidate_l2 =>
			address := x"81000008";
			data := CStoIM_sig.address(31 downto 5) & "00001"; -- invalidate a single line
			BUS_WRITE_SINGLE(address, data, dmao, v.dmai, r.busAccess, v.busAccess);

			if(v.busAccess.done = '1') then
				next_s <= invalidate_l1;
			else
				next_s <= invalidate_l2;
			end if;
			im_to_chipscope.im_current_s <= x"7";

		when invalidate_l1 =>
			address := CStoIM_sig.address(31 downto 5) & "00000";
			data := (others => '0');
			BUS_WRITE_SINGLE(address, data, dmao, v.dmai, r.busAccess, v.busAccess);
			v.busAccess.IdleTrans := '1';

			if(v.busAccess.done = '1') then
				v.busAccess.IdleTrans := '0'; -- Can be put down in bus_package once the grant is received (we shouldn't receive any splits for idle transactions). But this does no harm (better as we can see that IdleTrans is reset?)
				vc.invExe_cnt := rc.invExe_cnt + '1';
				next_s <= idle;
			else
				next_s <= invalidate_l1;
			end if;

			im_to_chipscope.im_current_s <= x"8";
-- Invalidation Execution (End)

-- Force Write-Through (Start)
		when force_write_through =>
			address := x"81000008";
			data := CStoIM_sig.address(31 downto 5) & "00010";
			BUS_WRITE_SINGLE(address, data, dmao, v.dmai, r.busAccess, v.busAccess);

			if(v.busAccess.done = '1') then
				vc.WB_cnt := rc.WB_cnt + '1';
				next_s <= idle;
			else
				next_s <= force_write_through;
			end if;

			im_to_chipscope.im_current_s <= x"9";
-- Force Write-Through (End)

-- Update Directory (Start)
		when update_sharing_table =>
			req <= '1';
			ram_enable <= '1';
			ram_write <= '1';
			ram_addr <= CStoIM_sig.address((ram_addr'high + 5) downto 5);
			ram_data_wr <= dir_update(ram_data_rd, to_integer(unsigned(CStoIM_sig.tile_src)));

			if r.rd_data_change /= rd_data_change then
				vc.dirUpdate_cnt := rc.dirUpdate_cnt + '1';
				if (evict_flag = '1') then
					v.evict_flag := '1';
					v.evict_address := evict_address;
					v.sharingVector := inv_tile_update(evict_data, my_tile_id); -- we can already prepare the sharingVector
					vc.eviction_cnt := rc.eviction_cnt + '1';
					next_s <= invalidation_generation;
				else
					next_s <= idle;
				end if;
			end if;
			im_to_chipscope.im_current_s <= x"A";
-- Update Directory (End)

		when others =>
			req <= '1';
			
			next_s <= idle;
			im_to_chipscope.im_current_s <= x"B";
	end case;

	t <= v;
	tc <= vc;
end process mainProcess;

dir_ram_n : if dir_mode = 1 generate
crm_dir_ram : entity icrm.ram_2p
	generic map(
		abits => abit,
		dbits => dbit,
		tech => tech
	) -- two additional bits are status bits
	port map(
		clk => clk,
		rst => rst,
		address1 => ram_addr,
		datain1 => ram_data_wr,
		dataout1 => ram_data_rd,
		en1 => ram_enable,
		we1 => ram_write,
		address2 => r_addr,
		datain2 => r_data_wr,
		dataout2 => r_data_rd,
		en2 => r_enable,
		we2 => r_write,
		address3 => r_addr_snoop,
		datain3 => r_data_wr_snoop,
		dataout3 => r_data_rd_snoop,
		en3 => r_enable_snoop,
		we3 => r_write_snoop,
		req1 => req,
		req2 => r_req,
		req3 => r_req_snoop,
		gnt1 => gnt,
		gnt2 => r_gnt,
		gnt3 => r_gnt_snoop,
		rd_data_change1 => rd_data_change
		--rd_data_change2 => rd_data_change2, --to be connected
		--rd_data_change3 => rd_data_change3
	);
end generate;

dir_ram : if dir_mode = 2 generate
crm_dir_ram : entity icrm.ram_2p_hs
	generic map(
		abits => abit,
		dbits => dbit,
		tech => tech,
		my_tile_id => my_tile_id,
		x_loc => x_loc,
		y_loc => y_loc,
		ways => 4,
		depth => 1024
	) -- two additional bits are status bits
	port map(
		clk => clk,
		rst => rst,
		crmLUT => r.crmLUT,
		protect_set => protect_set,
		address1 => ram_addr,
		datain1 => ram_data_wr,
		dataout1 => ram_data_rd,
		en1 => ram_enable,
		we1 => ram_write,
		address2 => r_addr,
		datain2 => r_data_wr,
		dataout2 => r_data_rd,
		en2 => r_enable,
		we2 => r_write,
		address3 => r_addr_snoop,
		datain3 => r_data_wr_snoop,
		dataout3 => r_data_rd_snoop,
		en3 => r_enable_snoop,
		we3 => r_write_snoop,
		req1 => req,
		req2 => r_req,
		req3 => r_req_snoop,
		gnt1 => gnt,
		gnt2 => r_gnt,
		gnt3 => r_gnt_snoop,
		evict_flag_IM => evict_flag,
		evict_data_IM => evict_data,
		evict_address_IM => evict_address,
		rd_data_change1 => rd_data_change,
		eviction_policy_IM => evictionPolicy_int
		--rd_data_change2 => rd_data_change2, --to be connected
		--rd_data_change3 => rd_data_change3
	);
end generate;

end architecture;
