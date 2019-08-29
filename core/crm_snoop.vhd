------------------------------------------------------------------------------
--  This file is a part of the GRLIB VHDL IP LIBRARY
--  Copyright (C) 2012, Aeroflex Gaisler AB - all rights reserved.
--
-- ANY USE OR REDISTRIBUTION IN PART OR IN WHOLE MUST BE HANDLED IN
-- ACCORDANCE WITH THE GAISLER LICENSE AGREEMENT AND MUST BE APPROVED
-- IN ADVANCE IN WRITING.
-----------------------------------------------------------------------------
-- Entity: 	crm_snoop
-- File:	crm_snoop.vhd
-- Author:	Ankit Kalbande
-- Description:	AHB trace unit that can have registers on a separate bus and
--              select between several trace buses.
------------------------------------------------------------------------------
use STD.textio.all;
library ieee;
use ieee.std_logic_1164.all;
USE ieee.numeric_std.ALL;
use ieee.std_logic_textio.all;
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
library icrm;
use icrm.crm_pkg.all;

entity crm_snoop is
generic(
	hindex			: integer := 0;
	ioaddr			: integer := 16#000#;
	iomask			: integer := 16#E00#;
	irq				: integer := 0;
	my_tile_id		: integer := 0;
	na_mst_rx_idx	: integer := 0
);

port(
    rst                 : in  std_ulogic;
    clk                 : in  std_ulogic;
    ahbsi               : in  ahb_slv_in_type;  -- Register interface
    ahbso               : out ahb_slv_out_type; -- Register interface
    ahbmi               : in  ahb_mst_in_type;  -- Trace interface
    CStoIM              : out CStoIM_type;    -- Fifo interface with CRM CORE
	counters			: in invManCnt_type;
	evictionPolicy		: out std_logic_vector(31 downto 0);
    wr_en               : out std_ulogic;   -- Fifo interface with CRM CORE
    full                : in std_ulogic;    -- Fifo interface with CRM CORE
    tile_src            : in std_logic_vector(log2x(dim_x*dim_y)-1 downto 0);   -- interface with NA
    cc_wr_en            : out std_ulogic;   -- Fifo interface with CRM Config
    cc_full             : in std_ulogic;
    cc_data_req         : out std_logic_vector(63 downto 0);
    cc_rd_en            : out std_ulogic;
    cc_empty            : in std_ulogic;
    cc_data_rsp         : in std_logic_vector(31 downto 0);
    crm_en              : out std_ulogic;
    r_addr_snoop        : out  std_logic_vector((abit - 1) downto 0);
    r_data_rd_snoop     : in std_logic_vector((dbit -1) downto 0);  --two additional bits are status bits
    r_data_wr_snoop     : out std_logic_vector((dbit -1) downto 0); --two additional bits are status bits
    r_enable_snoop      : out std_logic;
    r_write_snoop       : out std_logic;
    r_req_snoop         : out std_logic;
    r_gnt_snoop         : in std_logic;
    fifoDepth           : out std_logic_vector(31 downto 0);
    fifoCriticalLevel   : out std_logic_vector(15 downto 0);
    fifoSafeLevel       : out std_logic_vector(15 downto 0);
	fifoLevel			: in std_logic_vector(15 downto 0);
	almostFull			: in std_ulogic;
	cs_to_chipscope		: out crm_cs_chipscope_type
);
end;

architecture rtl of crm_snoop is
constant share_start	: std_logic_vector(31 downto 0) := share_addr_start;
constant share_end		: std_logic_vector(31 downto 0) := share_addr_end;

constant hconfig : ahb_config_type := (
	0 => ahb_device_reg (VENDOR_GAISLER, GAISLER_AHBTRACE, 0, 0, irq),
    4 => ahb_membar(ioaddr, '0', '0', iomask),
	others => zero32
	);

type state_type is (s0,s1,s2,s3,s3a,s4,s5,s6,s6a,s7,s8);

----------------------Signal decleration-----------

signal current_s, next_s : state_type;

signal tbi, tbi_in, tbi_hist : tracebuf_in_type;
signal r, rin : regtype;
signal rf, rfin : fregtype;
signal rc, rcin : counter_reg;
signal cb, cb_active : coherency_block_array;
signal sb : shared_block_array;

signal roc : integer;
signal roc_update, cb_active_update, mod_update_null, mod_update : std_ulogic;

signal enable : std_ulogic;
signal crmLUT_config : std_ulogic;

begin
crm_en <= r.enable;

-- ahb output configuration
ahbso.hindex <= hindex;
ahbso.hconfig <= hconfig;
ahbso.hirq <= (others => '0');
ahbso.hsplit <= (others => '0');
ahbso.hresp <= HRESP_OKAY;
ahbso.hrdata <= ahbdrivedata(r.hrdata);
ahbso.hready <= r.hready;

-- RAM arbiter Interface
r_addr_snoop <= r.dir_addr;
r_req_snoop <= r.dir_rd;
r_enable_snoop <= '1';
r_write_snoop <= '0';

-- Send Fifo Parameters
fifoDepth <= r.fifoDepth;
fifoCriticalLevel <= r.fifoCriticalLevel;
fifoSafeLevel <= r.fifoSafeLevel;

-- Send Cache Based Directory Paramenters
evictionPolicy <= r.evictionPolicy;

crm_snoop_bus : process(rst, ahbsi, ahbmi, r, rc, rf, tile_src, r_gnt_snoop ,r_data_rd_snoop, tbi_hist, tbi, cb, sb, counters, fifoLevel, almostFull)
variable v : regtype;
variable vf : fregtype;
variable regsd : std_logic_vector(31 downto 0);
variable vabufi, vabufi_hist : tracebuf_in_type;
variable regaddr : std_logic_vector(5 downto 2);
variable tbaddr  : std_logic_vector(3 downto 2);
variable cbindex : std_logic_vector(7 downto 0);
begin
    v := r;
	vf := rf;
    vabufi := tbi;
    vabufi_hist := tbi_hist;
    regsd := (others => '0');
    vabufi.enable := '0';
    vabufi.data := (others => '0');
    vabufi.write := '0';
    vabufi.tile_src := tile_src;
    v.hready := r.hready2; v.hready2 := r.hready3; v.hready3 := '0';
    v.ctr_word := (others => '0'); v.trans_code := (others => '0'); v.trigger := '0';
    v.cb_write := '0'; v.cb_addr := (others => '0'); v.cb_data := (others => '0');
    v.sb_write := '0'; v.sb_addr := (others => '0'); v.sb_data := (others => '0');

    regaddr := r.haddr(5 downto 2);
    tbaddr := r.haddr(3 downto 2);
    cbindex := r.haddr(11 downto 4);

	if r_gnt_snoop = '1' then
		v.sharing_vector := r_data_rd_snoop;
		v.dir_addr := (others => '0');
		v.dir_rd := '0';
	end if;

-- generate buffer inputs
	vabufi.write := '0';
    if r.enable = '1' then
        vabufi.tile_src := tile_src;
		vabufi.data(127 downto 96) := (others => '0');	--r.timer;
        vabufi.data(95) := '0';
        vabufi.data(94 downto 80) := ahbmi.hirq(15 downto 1);
        vabufi.data(79) := r.thwrite;
        vabufi.data(78 downto 77) := r.thtrans;
        vabufi.data(76 downto 74) := r.thsize;
        vabufi.data(73 downto 71) := r.thburst;
        vabufi.data(70 downto 67) := r.thmaster;
        vabufi.data(66) := r.thmastlock;
        vabufi.data(65 downto 64) := ahbmi.hresp;

        if r.thwrite = '1' then
            vabufi.data(63 downto 32) := ahbsi.hwdata(31 downto 0);
        else
            vabufi.data(63 downto 32) := ahbmi.hrdata(31 downto 0);
        end if;

        vabufi.data(31 downto 0) := r.thaddr;
    else
        vabufi.data := ahbsi.hwdata(31 downto 0) & ahbsi.hwdata(31 downto 0) &
                       ahbsi.hwdata(31 downto 0) & ahbsi.hwdata(31 downto 0);
    end if;

-- write trace buffer
    if r.enable = '1' then
        if (r.ahbactive and ahbsi.hready) = '1' then
            if not (ahb_filt_hit(r, rf)) then
                vabufi.enable := '1';
                vabufi.write := '1';
            end if;
        end if;
    end if;

-- save AHB transfer parameters
    if (ahbsi.hready = '1') then
        v.thaddr := ahbsi.haddr;
        v.thwrite := ahbsi.hwrite;
        v.thtrans := ahbsi.htrans;
        v.thsize := ahbsi.hsize;
        v.thburst := ahbsi.hburst;
        v.thmaster := ahbsi.hmaster;
        v.thmastlock := ahbsi.hmastlock;
        v.ahbactive := ahbsi.htrans(1);

        vf.shsel := ahbsi.hsel;
    end if;

-- AHB transfer parameters for register accesses
    if (ahbsi.hready = '1' ) then
        v.haddr := ahbsi.haddr(31 downto 2);
        v.hwrite := ahbsi.hwrite;
        v.regacc := ahbsi.haddr(15 downto 12);
		v.hsel := ahbsi.htrans(1) and ahbsi.hsel(hindex);	-- SlaveSelect is me and htrans is not idle/busy (seq/nseq)
    end if;

-- AHB slave access to DSU registers and Directory
	if (r.hsel and not r.hready) = '1' then
		if r.regacc = "0000" then	-- registers read/write access
            v.hready := '1';
            case regaddr is
				when "0000" =>
                    regsd(0) := r.enable;
                    regsd(1) := rf.f_write;
                    regsd(2) := rf.f_read;
                    regsd(3) := '0';
                    regsd(4) := '0';
                    regsd(5) := rf.f_retry;
                    regsd(6) := '0';
                    regsd(7) := rf.f_update;
                    regsd(8) := rf.f_write_back;
                    regsd(9) := rf.f_invalidation_gen;
                    regsd(10) := rf.f_invalidation_exe;
                    regsd(11) := rf.f_performance_counter;

                    if r.hwrite = '1' then
                        vf.f_write := ahbsi.hwdata(1);
                        vf.f_read := ahbsi.hwdata(2);
                        vf.f_retry := ahbsi.hwdata(5);
                        vf.f_update := ahbsi.hwdata(7);
                        vf.f_write_back := ahbsi.hwdata(8);
                        vf.f_invalidation_gen := ahbsi.hwdata(9);
                        vf.f_invalidation_exe := ahbsi.hwdata(10);
                        vf.f_performance_counter := ahbsi.hwdata(11);
                        v.enable := ahbsi.hwdata(0);
                    end if;

				when "0001" =>
                    regsd := rf.mmask;
                    if r.hwrite = '1' then
                        vf.mmask := ahbsi.hwdata(31 downto 0);
                    end if;

				when "0010" =>
                    regsd := rf.smask;
                    if r.hwrite = '1' then
                        vf.smask := ahbsi.hwdata(31 downto 0);
                    end if;

                when "0011" =>
                    regsd := rc.master_counter;

                when "0100" =>
					regsd := counters.dirUpdate_cnt;

                when "0101" =>
					regsd := counters.WB_cnt;

                when "0110" =>
					regsd := counters.invGen_cnt;

                when "0111" =>
					regsd := counters.invExe_cnt;

                when "1000" =>
					regsd := (others => '0');	--r.ctr_word;
                    if r.hwrite = '1' then
                        v.ctr_word := ahbsi.hwdata(31 downto 0);
                        v.trans_code := "0000";
                        v.trigger := '1';
                    end if;

                when "1001" =>
                    regsd := rc.full_counterIG;

				when "1010" =>
                    regsd := rc.full_counterIE;
                    
--				when "1011" =>
--					regsd := zeros_32(31 downto dbit) & r.sharing_vector;
--					if r.hwrite = '1' then
--						v.dir_addr := ahbsi.hwdata((r.dir_addr'high+5) downto 5);
--						v.dir_rd := '1';
--					end if;

				when "1011" =>
					regsd(31) := almostFull;
					regsd(30 downto 16) := zeros_32(30 downto 16);
					regsd(15 downto 0) := fifoLevel;

				when "1100" =>
					regsd(31 downto 16) := r.fifoCriticalLevel;
					regsd(15 downto 0) := r.fifoSafeLevel;
					if r.hwrite = '1' then
						v.fifoCriticalLevel := ahbsi.hwdata(31 downto 16);
						v.fifoSafeLevel := ahbsi.hwdata(15 downto 0);
					end if;

				when "1101" =>
					regsd := r.fifoDepth;
					if r.hwrite = '1' then
						v.fifoDepth := ahbsi.hwdata(31 downto 0);
					end if;

				when "1110" =>
					regsd := r.evictionPolicy;
					if r.hwrite = '1' then
						v.evictionPolicy := ahbsi.hwdata(31 downto 0);
					end if;

				when "1111" =>
					regsd := counters.eviction_cnt;
                    
				when others =>
                    regsd := (others => '1');
            end case;

            v.hrdata := regsd;

		elsif r.regacc = "0001" then    -- read/write access to coherency blocks
            v.hready := '1';
            case tbaddr is
                when "00" =>
					regsd((dim_x*dim_y)-1 downto 0) := cb(to_integer(unsigned(cbindex))).tiles;
                    if r.hwrite = '1' then
                        v.cb_write := '1';
                        v.cb_data:= ahbsi.hwdata;
						v.cb_addr:= "00" & cbindex;
                    end if;

                when "01" =>
					regsd := cb(to_integer(unsigned(cbindex))).start_addr;
                    if r.hwrite = '1' then
                        v.cb_write := '1';
                        v.cb_data:= ahbsi.hwdata;
						v.cb_addr:= "01" & cbindex;
                    end if;

				when "10" =>
					regsd := cb(to_integer(unsigned(cbindex))).end_addr;
                    if r.hwrite = '1' then
                        v.cb_write := '1';
                        v.cb_data:= ahbsi.hwdata;
						v.cb_addr:= "10" & cbindex;
                    end if;

                when others =>
					regsd := cb(to_integer(unsigned(cbindex))).id;
                    if r.hwrite = '1' then
                        v.cb_write := '1';
                        v.cb_data:= ahbsi.hwdata;
						v.cb_addr:= "11" & cbindex;
                    end if;
            end case;

            v.hrdata := regsd;

		elsif r.regacc = "0010" then    -- read/write access to shared blocks
            v.hready := '1';
            case tbaddr is
                 when "00" =>
                    regsd := sb(to_integer(unsigned(cbindex))).id;
                    if r.hwrite = '1' then
                        v.sb_write := '1';
                        v.sb_data:= ahbsi.hwdata;
                        v.sb_addr:= "00" & cbindex;
                    end if;

				when "01" =>
                    regsd := sb(to_integer(unsigned(cbindex))).start_addr;
                    if r.hwrite = '1' then
                        v.sb_write := '1';
                        v.sb_data:= ahbsi.hwdata;
                        v.sb_addr:= "01" & cbindex;
                    end if;

				when "10" =>
                    regsd := sb(to_integer(unsigned(cbindex))).end_addr;
                    if r.hwrite = '1' then
                        v.sb_write := '1';
                        v.sb_data:= ahbsi.hwdata;
                        v.sb_addr:= "10" & cbindex;
                    end if;

                when others =>
                    regsd := (others => '0');
                    if r.hwrite = '1' then
                        v.sb_write := '0';
                        v.sb_data:= ahbsi.hwdata;
                        v.sb_addr:= "11" & cbindex;
                    end if;
            end case;

            v.hrdata := regsd;

        else    -- unmapped address
            v.hready := '1';
            regsd := (others => '0');
            v.hrdata := regsd;
        end if;
    end if;

-- hready signal handler
    if ((ahbsi.hsel(hindex) and ahbsi.hready) = '1') and ((ahbsi.htrans = HTRANS_BUSY) or (ahbsi.htrans = HTRANS_IDLE)) then
        v.hready := '1';
    end if;

-- reset handeling
    if rst = '0' then
        v.ahbactive := '0';
        v.enable := '0';
        v.hsel := '0';
        v.regacc := (others => '0');
        v.hready := '1';
        vf.shsel:= (others => '0');
        vf.smask:= (others => '0');
        vf.mmask:= (others => '0');     -- (Akshay 03Nov17) Copy Paste Error -> mmask was not reset (which works fine in ModelSim as the default value is 0), but would not work on chipIT (default reset value = 1). Therefore, this would trigger ahb_filt_hit unwantedly thereby never activating enable.
        vf.f_read := '0';
        vf.f_write := '0';
        vf.f_retry := '0';
        vf.f_update:= '0';
        vf.f_write_back := '0';
        vf.f_invalidation_exe := '0';
        vf.f_invalidation_gen := '0';
        vf.f_performance_counter:= '0';
    end if;

-- final assignments
    tbi_hist <= vabufi_hist;
    tbi_in <= vabufi;
    rin <= v;
    rfin <= vf;
end process;


clkProcess : process(clk,rst)
begin
	if (rst /= '1') then
		current_s <= s0;
	elsif rising_edge(clk) then
		current_s <= next_s;
        r <= rin;
        rf <= rfin;
        tbi <= tbi_in;
        enable <= tbi_in.enable;
		if(roc_update = '1') then
			roc <= cr_mod_id(cb);
		end if;
    end if;
end process;

crm_tableUpdates : process(rst, clk)
begin
    if(rst /= '1') then
        for i in 0 to (COHERENCY_BLOCK_ARRAY_SIZE - 1) loop
            cb(i).id <= (others => '0');
            cb(i).tiles <= (others => '0');
            cb(i).start_addr <= (others => '0');
            cb(i).end_addr <= (others => '0');
            ---------------------------------
            cb_active(i).id <= (others => '0');
            cb_active(i).tiles <= (others => '0');
            cb_active(i).start_addr <= (others => '0');
            cb_active(i).end_addr <= (others => '0');
            ---------------------------------
        end loop;

        for i in 0 to (SHARED_BLOCK_ARRAY_SIZE - 1) loop
            sb(i).id <= (others => '0');
            sb(i).start_addr <= (others => '0');
            sb(i).end_addr <= (others => '0');
        end loop;

        rc <= ((others => (others => '0')));
        crmLUT_config <= '0';

    elsif rising_edge(clk) then
		crmLUT_config <= '0';
        if(r.cb_write = '1' and (to_integer(unsigned(r.cb_addr(7 downto 0))) < COHERENCY_BLOCK_ARRAY_SIZE)) then
            case r.cb_addr(9 downto 8) is
				when "00" => cb(to_integer(unsigned(r.cb_addr(7 downto 0)))).tiles <= r.cb_data((dim_x*dim_y)-1 downto 0);
				when "01" => cb(to_integer(unsigned(r.cb_addr(7 downto 0)))).start_addr <= r.cb_data;
				when "10" => cb(to_integer(unsigned(r.cb_addr(7 downto 0)))).end_addr <= r.cb_data;
				when others => cb(to_integer(unsigned(r.cb_addr(7 downto 0)))).id <= r.cb_data(31) & '1' & r.cb_data(29 downto 0);
            end case;
        end if;

        if(r.sb_write = '1' and (to_integer(unsigned(r.cb_addr(7 downto 0))) < SHARED_BLOCK_ARRAY_SIZE)) then
            case r.sb_addr(9 downto 8) is
				when "00" => sb(to_integer(unsigned(r.sb_addr(7 downto 0)))).id <= r.sb_data;
                when "01" => sb(to_integer(unsigned(r.sb_addr(7 downto 0)))).start_addr <= r.sb_data;
				when others => sb(to_integer(unsigned(r.sb_addr(7 downto 0)))).end_addr <= r.sb_data;
                end case;
        end if;

        if(cb_active_update = '1') then
            cb_active(to_integer(unsigned(cc_data_rsp(7 downto 0)))) <= cb(to_integer(unsigned(cc_data_rsp(7 downto 0))));
            cb_active(to_integer(unsigned(cc_data_rsp(7 downto 0)))).id(30) <= '0';
        end if;

        if(mod_update = '1') then
            cb(roc).id(30) <= '0';
            cb_active(roc).id(30) <= '1';
        end if;

        if(mod_update_null = '1') then
            cb_active(roc).tiles <= cb(roc).tiles;
            cb_active(roc).start_addr <= cb(roc).start_addr;
            cb_active(roc).end_addr <= cb(roc).end_addr;
            cb_active(roc).id <=cb(roc).id(31) &'0'& cb(roc).id(29 downto 0);
            cb(roc).id(30) <= '0';
            crmLUT_config <= '1';
        end if;

    rc <= rcin;

    end if;
end process;

cs_to_chipscope.cs_full <= full;
cs_to_chipscope.cs_enable <= enable;
cs_to_chipscope.cs_cr_filt_hit <= '1' when (cr_filt_hit(tbi, cb_active) = true) else '0';
cs_to_chipscope.cs_sb_filt_hit <= '1' when (sb_filt_hit(tbi, sb) = true) else '0';
cs_to_chipscope.cs_cr_filt_tile <= (cr_filt_tile(tbi, cb_active)(to_integer(unsigned(tbi.tile_src))));
cs_to_chipscope.cs_tbi_data_rdwr <= tbi.data(79);
cs_to_chipscope.cs_tbi_data_trans <= tbi.data(78 downto 77);
cs_to_chipscope.cs_tbi_data_namst <= tbi.data(70 downto 67);
cs_to_chipscope.cs_tbi_data_split <= tbi.data(65 downto 64);
cs_to_chipscope.cs_tbi_data_addr <= tbi.data(31 downto 0);
cs_to_chipscope.cs_ahb_filt_hit <= '1' when (ahb_filt_hit(r, rf) = true) else '0';

crm_fifo_interface : process(full, enable, tbi, r.trigger, crmLUT_config, rc, cb_active, sb, roc)         -- (Akshay 06Oct17, crm_sens) Observed that the process may not be triggered in cases where the existing sensitivity list does not change, but the tbi.data signal changes which leads to not triggering the wr_en -> Added the tbi.data signal to the sensitivity list. Removed tbi.write from the sensitivity list as its the same as enable.
variable L : line;
variable vc : counter_reg;
begin
    vc := rc;

    if(tbi.data(70 downto 67) = std_logic_vector(to_unsigned(na_mst_rx_idx, 4))) then CStoIM.tile_src <= std_logic_vector(resize(unsigned(tbi.tile_src),8));
    else
        CStoIM.tile_src <= std_logic_vector(to_unsigned(my_tile_id, 8));
    end if;

    -- Snooped a Read on the BUS performed by the NA to an address which lies in my local config table (what I share with others => I have to make note of this remote tile in my DIR)
    if(full = '0' and enable = '1' and tbi.data(79) = '0' and cr_filt_hit(tbi, cb_active) and tbi.data(70 downto 67) = std_logic_vector(to_unsigned(na_mst_rx_idx, 4)) and (tbi.data(78 downto 77) = HTRANS_NONSEQ) --or tbi.data(78 downto 77) = HTRANS_SEQ)
    and cr_filt_tile(tbi, cb_active)(to_integer(unsigned(tbi.tile_src))) = '1' and (tbi.data(31 downto 0) >= share_start) and (tbi.data(31 downto 0) <= share_end)) then
        wr_en <= '1';
        CStoIM.data <= (others => '0');
        CStoIM.address <= tbi.data(31 downto 5)& '0' & "0010";
        vc.master_counter := rc.master_counter + '1';
        vc.update_counter := rc.update_counter + '1';
		cs_to_chipscope.cs_fifoIF_stage <= x"1";

    -- Snooped a Write on the BUS performed by the TILE to an address which lies in my remote config table (what others share with me => I have to force a write back to that REMOTE TILE)
    -- How we sure that the TILE performed this: Since we are searching in the remote config table that contains only remote addresses, we can be sure that this write did not originate from the NA
    elsif(full = '0' and enable = '1' and tbi.data(79) = '1' and sb_filt_hit(tbi, sb) and (tbi.data(65 downto 64) /= HRESP_SPLIT) and (tbi.data(78 downto 77) = HTRANS_NONSEQ) --or tbi.data(78 downto 77) = HTRANS_SEQ) (Akshay 17Oct17, Do no trigger a WB if the write request was split by the slave -> as this would lead to unnecessary WBs)
    ) then
        wr_en <= '1';
        CStoIM.data <= (others => '0');
        CStoIM.address <= tbi.data(31 downto 5)& '0' & "0011"; -- changed here 0011
        vc.master_counter := rc.master_counter + '1';
        vc.writeback_counter := rc.writeback_counter + '1';
		cs_to_chipscope.cs_fifoIF_stage <= x"2";

    -- Snooped a Write on the BUS performed by the TILE to an address which lies in my local config table (what I share with others => I need to possibly send out INVs if someone had previously read data from me)
    elsif(full = '0' and enable = '1' and tbi.data(79) = '1' and cr_filt_hit(tbi, cb_active)
    and ((tbi.data(78 downto 77) = HTRANS_NONSEQ) or (tbi.data(73 downto 71) = HBURST_INCR and tbi.data(78 downto 77) = HTRANS_SEQ and tbi.data(4 downto 0) = "00000" and tbi.data(70 downto 67) = std_logic_vector(to_unsigned(na_mst_rx_idx, 4)))) -- Normal Write or Burst Write(DMAs) (Akshay 10Jan18) CRM now sends out INVs on DMA (burst) writes as well
    and (tbi.data(31 downto 0) >= share_start) and (tbi.data(31 downto 0) <= share_end)) then

        wr_en <= '1';
--        CStoIM.data <= cr_filt_tile(tbi, cb_active);
        CStoIM.data <= (others => '0');
        CStoIM.address <= tbi.data(31 downto 5)& '0' & "0001";  -- changed here 0001
        vc.master_counter := rc.master_counter + '1';
        vc.invalidation_gen_counter := rc.invalidation_gen_counter + '1';
		cs_to_chipscope.cs_fifoIF_stage <= x"3";

    -- Received an INV
    elsif(full = '0' and r.trigger = '1') then
        wr_en <= '1';
        CStoIM.data <= (others => '0');
        CStoIM.address <= r.ctr_word(31 downto 5)& '0' & r.trans_code;
        vc.master_counter := rc.master_counter + '1';
        vc.invalidation_exe_counter := rc.invalidation_exe_counter + '1';
		cs_to_chipscope.cs_fifoIF_stage <= x"4";

    elsif(full = '0' and crmLUT_config = '1') then
        wr_en <= '1';
        CStoIM.data <= cb_active(roc).tiles;
        CStoIM.address <= zeros_32(31 downto 4) & "0100";
        vc.master_counter := rc.master_counter + '1';
		cs_to_chipscope.cs_fifoIF_stage <= x"5";
        
    elsif(full = '1' and enable = '1' and tbi.data(79) = '1' and cr_filt_hit(tbi, cb_active)
    and ((tbi.data(78 downto 77) = HTRANS_NONSEQ) or (tbi.data(73 downto 71) = HBURST_INCR and tbi.data(78 downto 77) = HTRANS_SEQ and tbi.data(4 downto 0) = "00000" and tbi.data(70 downto 67) = std_logic_vector(to_unsigned(na_mst_rx_idx, 4)))) -- Normal Write or Burst Write(DMAs) (Akshay 10Jan18) CRM now sends out INVs on DMA (burst) writes as well
    and (tbi.data(31 downto 0) >= share_start) and (tbi.data(31 downto 0) <= share_end)) then
        wr_en <= '0';
        CStoIM.data <= (others => '0');
        CStoIM.address <= (others => '0');
        vc.full_counterIG := rc.full_counterIG + '1';
		cs_to_chipscope.cs_fifoIF_stage <= x"6";
        
    elsif(full = '1' and r.trigger = '1') then
        wr_en <= '0';
        CStoIM.data <= (others => '0');
        CStoIM.address <= (others => '0');
        vc.full_counterIE := rc.full_counterIE + '1';
		cs_to_chipscope.cs_fifoIF_stage <= x"7";

    else
        wr_en <= '0';
        CStoIM.data <= (others => '0');
        CStoIM.address <= (others => '0');
		cs_to_chipscope.cs_fifoIF_stage <= x"0";
    end if;

    rcin <= vc;

end process;

crm_configuration : process(current_s, cb, cb_active, cc_full, cc_empty, roc)
begin
	next_s <= current_s;
    roc_update <= '0';
    cc_rd_en <= '0';
	cc_wr_en <= '0';
	cc_data_req <= (others => '0');
    cb_active_update <= '0';
    mod_update <= '0';
    mod_update_null <= '0';

    case current_s is
		 when s0 =>
            roc_update <= '1';

			if cc_empty = '0' then
				next_s <= s6;
			elsif(cr_mod(cb)) then
				next_s <= s1;
			else
				next_s <= s0;
			end if;
			cs_to_chipscope.cs_config_state <= x"0";

		when s1 =>
			if(cc_full = '0') then
				if(cb_active(roc).id = x"00000000" and cb(roc).id(29) = '1') then
					next_s <= s2;   ----initialization of coherency region for the first time
				elsif(cb_active(roc).tiles /= cb(roc).tiles and cb(roc).id(29) = '1') then
					next_s <= s3;
				elsif(cb_active(roc).start_addr /= cb(roc).start_addr and cb(roc).id(29) = '1') then
					next_s <= s4;
				elsif(cb_active(roc).end_addr /= cb(roc).end_addr and cb(roc).id(29) = '1') then
					next_s <= s5;
				else
					next_s <= s8;
				end if;
			else
				next_s <= s1;
			end if;
			cs_to_chipscope.cs_config_state <= x"1";

		when s2 =>
            cc_wr_en <= '1';
            cc_data_req <= cb(roc).start_addr(22 downto 5) & cb(roc).end_addr(22 downto 5) & zeros_32(27 downto 11) & std_logic_vector(to_unsigned(roc, 8)) & "000";

			next_s <= s7;
			cs_to_chipscope.cs_config_state <= x"2";

		when s3 =>
            cc_wr_en <= '1';
            if(cb(roc).start_addr >= cb_active(roc).start_addr and cb(roc).end_addr >= cb_active(roc).end_addr) then
                cc_data_req <= cb(roc).start_addr(22 downto 5) & cb_active(roc).end_addr(22 downto 5) & zeros_32(27 downto 11) & std_logic_vector(to_unsigned(roc, 8)) & "001";
            elsif(cb(roc).start_addr <= cb_active(roc).start_addr and cb(roc).end_addr >= cb_active(roc).end_addr) then
                cc_data_req <= cb_active(roc).start_addr(22 downto 5) & cb_active(roc).end_addr(22 downto 5) & zeros_32(27 downto 11) & std_logic_vector(to_unsigned(roc, 8)) & "001";
            elsif(cb(roc).start_addr <= cb_active(roc).start_addr and cb(roc).end_addr <= cb_active(roc).end_addr) then
                cc_data_req <= cb_active(roc).start_addr(22 downto 5) & cb(roc).end_addr(22 downto 5) & zeros_32(27 downto 11) & std_logic_vector(to_unsigned(roc, 8)) & "001";
            else
                cc_data_req <= cb(roc).start_addr(22 downto 5) & cb(roc).end_addr(22 downto 5) & zeros_32(27 downto 11) & std_logic_vector(to_unsigned(roc, 8)) & "001";
            end if;

			if(cc_full = '0') then
				next_s <= s3a;
			else
				next_s <= s3;
			end if;
			cs_to_chipscope.cs_config_state <= x"3";

		when s3a =>
            cc_wr_en <= '1';
            cc_data_req <= zeros_32(31 downto 0) & zeros_32(31 downto (2*dim_x*dim_y)) & cb(roc).tiles & cb_active(roc).tiles;

			if(cc_full = '0') then
				if(cb_active(roc).start_addr /= cb(roc).start_addr) then
					next_s <= s4;
				elsif(cb_active(roc).end_addr /= cb(roc).end_addr) then
					next_s <= s5;
				else
					next_s <= s7;
				end if;
			else
				next_s <= s3a;
			end if;
			cs_to_chipscope.cs_config_state <= x"4";

		when s4 =>
            cc_wr_en <= '1';
            if (cb(roc).start_addr > cb_active(roc).start_addr) then
                cc_data_req <= cb_active(roc).start_addr(22 downto 5) & cb(roc).start_addr(22 downto 5) & zeros_32(27 downto 11) & std_logic_vector(to_unsigned(roc, 8)) & "000";
            else
                cc_data_req <= cb(roc).start_addr(22 downto 5) & cb_active(roc).start_addr(22 downto 5) & zeros_32(27 downto 11) & std_logic_vector(to_unsigned(roc, 8)) & "000";
            end if;

			if(cc_full = '0') then
				if(cb_active(roc).end_addr /= cb(roc).end_addr) then
					next_s <= s5;
				else
					next_s <= s7;
				end if;
			else
				next_s <= s4;
			end if;
			cs_to_chipscope.cs_config_state <= x"5";

		when s5 =>
            cc_wr_en <= '1';
            if (cb(roc).end_addr > cb_active(roc).end_addr) then
                cc_data_req <= cb_active(roc).end_addr(22 downto 5) & cb(roc).end_addr(22 downto 5) & zeros_32(27 downto 11) & std_logic_vector(to_unsigned(roc, 8)) & "000";
            else
                cc_data_req <= cb(roc).end_addr(22 downto 5) & cb_active(roc).end_addr(22 downto 5) & zeros_32(27 downto 11) & std_logic_vector(to_unsigned(roc, 8)) & "000";
            end if;

			next_s <= s7;
			cs_to_chipscope.cs_config_state <= x"6";

		when s6 =>
            cc_rd_en <= '1';

			next_s <= s6a;
			cs_to_chipscope.cs_config_state <= x"7";

        when s6a =>
            cb_active_update <='1';

			next_s <= s0;
			cs_to_chipscope.cs_config_state <= x"8";

        when s7 =>
            cc_wr_en <= '1';
            cc_data_req <= zeros_32 & zeros_32(31 downto 11) & std_logic_vector(to_unsigned(roc, 8)) & "111";
            mod_update <='1';

			next_s <= s0;
			cs_to_chipscope.cs_config_state <= x"9";

        when s8 =>
            mod_update_null <='1';

			next_s <= s0;
			cs_to_chipscope.cs_config_state <= x"A";

		when others =>
			next_s <= s0;
			cs_to_chipscope.cs_config_state <= x"B";

    end case;
end process;

end;
