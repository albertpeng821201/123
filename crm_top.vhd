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
library top;
use top.config.all;
use top.config_types.all;
library icrm;
use icrm.crm_pkg.all;
use icrm.all;
library ina;
library ina_pkg;
use ina_pkg.ina_config.all;

entity crm_top is
  generic(
	x_loc			: integer := 0;
	y_loc			: integer := 0;
	hindex_im		: integer := 0;
	hirq_im			: integer := 0;
	venid_im		: integer := VENDOR_GAISLER;
	devid_im		: integer := 0;
	version_im		: integer := 0;
	incaddr_im		: integer := 0;
	my_tile_id		: integer := 0;
	hindex_snoop	: integer := 0;
	ioaddr_snoop	: integer := 16#000#;
	iomask_snoop	: integer := 16#E00#;
	tech_snoop		: integer := DEFMEMTECH;
	irq_snoop		: integer := 0;
	na_mst_rx_idx	: integer := 0
    );

  port(
	rstn			: in  std_ulogic;
	clkm			: in  std_ulogic;
	ahbsi			: in  ahb_slv_in_type;
	ahbso			: out ahb_slv_out_type;
	ahbmi			: in  ahb_mst_in_type;
	ahbmo			: out ahb_mst_out_type;
	tile_src		: in std_logic_vector(log2x(dim_x*dim_y)-1 downto 0);
	crm_en			: out std_ulogic
	);
end;

architecture rtl of crm_top is

signal dummy : CStoIM_type;
constant CStoIM_type_size : integer := ((dummy.tile_src'high + 1) + (dummy.data'high + 1) + (dummy.address'high + 1));
signal counters : invManCnt_type := invManCnt_type_default;
signal evictionPolicy : std_logic_vector(31 downto 0) := (others => '0');

signal wr_en : std_ulogic;
signal data_in_CStoIM : CStoIM_type;
signal data_in : std_logic_vector((CStoIM_type_size - 1) downto 0);
signal rd_en :std_ulogic;
signal data_out : std_logic_vector((CStoIM_type_size - 1) downto 0);
signal data_out_CStoIM : CStoIM_type;
signal empty : std_ulogic;
signal full : std_ulogic;
signal almost_full_sig : std_ulogic;
signal fifoLevel_sig : std_logic_vector(15 downto 0);

signal fifoDepth : std_logic_vector(31 downto 0);
signal fifoCriticalLevel : std_logic_vector(15 downto 0);
signal fifoSafeLevel : std_logic_vector(15 downto 0);

signal fifoDepth_pos : natural;
signal fifoCriticalLevel_pos : natural;
signal fifoSafeLevel_pos : natural;

signal req_wr_en : std_ulogic;
signal req_data_in : std_logic_vector(63 downto 0);
signal req_rd_en :std_ulogic;
signal req_data_out : std_logic_vector(63 downto 0);
signal req_empty : std_ulogic;
signal req_full : std_ulogic;

signal rsp_wr_en : std_ulogic;
signal rsp_data_in : std_logic_vector(31 downto 0);
signal rsp_rd_en :std_ulogic;
signal rsp_data_out : std_logic_vector(31 downto 0);
signal rsp_empty : std_ulogic;
signal rsp_full : std_ulogic;

signal ram_addr :  std_logic_vector((abit - 1) downto 0);
signal ram_data_rd :  std_logic_vector((dbit -1) downto 0); --two additional bits are status bits
signal ram_data_wr :  std_logic_vector((dbit -1) downto 0); --two additional bits are status bits
signal ram_enable :  std_logic;
signal ram_write :  std_logic;
signal ram_req : std_logic;
signal ram_gnt : std_logic;

signal ram_addr_snoop :  std_logic_vector((abit - 1) downto 0);
signal ram_data_rd_snoop :  std_logic_vector((dbit -1) downto 0); --two additional bits are status bits
signal ram_data_wr_snoop :  std_logic_vector((dbit -1) downto 0); --two additional bits are status bits
signal ram_enable_snoop :  std_logic;
signal ram_write_snoop :  std_logic;
signal ram_req_snoop : std_logic;
signal ram_gnt_snoop : std_logic;

signal ahbso_chipscope : ahb_slv_out_type;
signal ahbmo_chipscope: ahb_mst_out_type;

signal cs_to_chipscope : crm_cs_chipscope_type;
signal im_to_chipscope : crm_im_chipscope_type;
signal top_to_chipscope : crm_top_chipscope_type;
signal ila_crm_data : std_logic_vector(399 downto 0);

component ila_icrm
	port(
		clk : in std_logic;
		probe0 : in std_logic_vector(399 downto 0)
	);
end component;

begin

en_ila_icrm : if tile_config(y_loc,x_loc).dbg.en_ila_icrm = 1 generate
	ila_crm_data(31 downto 0)			<= ahbsi.haddr;
	ila_crm_data(33 downto 32)			<= ahbsi.htrans;
	ila_crm_data(34)					<= ahbsi.hwrite;
	ila_crm_data(35)					<= ahbsi.hready;
	ila_crm_data(39 downto 36)			<= ahbsi.hmaster;

	ila_crm_data(55 downto 40)			<= ahbmi.hgrant;
	ila_crm_data(57 downto 56)			<= ahbmi.hresp;

	ila_crm_data(59 downto 58)			<= ahbso_chipscope.hresp;
	ila_crm_data(75 downto 60)			<= ahbso_chipscope.hsplit;

	ila_crm_data(76)					<= ahbmo_chipscope.hbusreq;
	ila_crm_data(78 downto 77)			<= ahbmo_chipscope.htrans;
	ila_crm_data(79)					<= ahbmo_chipscope.hwrite;
	ila_crm_data(111 downto 80)			<= ahbmo_chipscope.hwdata;

	ila_crm_data(112)					<= cs_to_chipscope.cs_full;
	ila_crm_data(113)					<= cs_to_chipscope.cs_enable;
	ila_crm_data(114)					<= cs_to_chipscope.cs_cr_filt_hit;
	ila_crm_data(115)					<= cs_to_chipscope.cs_sb_filt_hit;
	ila_crm_data(116)					<= cs_to_chipscope.cs_cr_filt_tile;
	ila_crm_data(117)					<= cs_to_chipscope.cs_tbi_data_rdwr;
	ila_crm_data(119 downto 118)		<= cs_to_chipscope.cs_tbi_data_trans;
	ila_crm_data(123 downto 120)		<= cs_to_chipscope.cs_tbi_data_namst;
	ila_crm_data(125 downto 124)		<= cs_to_chipscope.cs_tbi_data_split;
	ila_crm_data(157 downto 126)		<= cs_to_chipscope.cs_tbi_data_addr;
	ila_crm_data(161 downto 158)		<= cs_to_chipscope.cs_fifoIF_stage;
	ila_crm_data(165 downto 162)		<= cs_to_chipscope.cs_config_state;

	ila_crm_data(181 downto 166)		<= fifoLevel_sig;
	ila_crm_data(182)					<= almost_full_sig;
	ila_crm_data(200 downto 183)		<= (others => '0');	-- unused bits

	ila_crm_data(204 downto 201)		<= im_to_chipscope.im_current_s;
	ila_crm_data(205)					<= im_to_chipscope.im_IdleTrans;
	ila_crm_data(206)					<= im_to_chipscope.im_busAccess_done;

	RS4_SV : if (region_size = 4) generate
		ila_crm_data(209 downto 207)	<= im_to_chipscope.im_sharingVector;
		ila_crm_data(221 downto 210)	<= (others => '0');
	end generate;
	RS8_SV : if (region_size = 8) generate
		ila_crm_data(213 downto 207)	<= im_to_chipscope.im_sharingVector;
		ila_crm_data(221 downto 214)	<= (others => '0');
	end generate;
	RS16_SV : if (region_size = 16) generate
		ila_crm_data(221 downto 207)	<= im_to_chipscope.im_sharingVector;
	end generate;

	ila_crm_data(253 downto 222)		<= im_to_chipscope.im_dmai.address;
	ila_crm_data(285 downto 254)		<= im_to_chipscope.im_dmai.data;
	ila_crm_data(286)					<= im_to_chipscope.im_dmai.request;
	ila_crm_data(287)					<= im_to_chipscope.im_dmao.ready;
	ila_crm_data(288)					<= im_to_chipscope.im_dmao.retry;
	ila_crm_data(289)					<= im_to_chipscope.im_dmao.grant;

	ila_crm_data(290)					<= im_to_chipscope.im_ram_write;
	ila_crm_data(291)					<= im_to_chipscope.im_ram_enable;
	ila_crm_data(309 downto 292)		<= im_to_chipscope.im_ram_addr;

	RS4_RAM : if (region_size = 4) generate
		ila_crm_data(314 downto 310)	<= im_to_chipscope.im_ram_data_rd;
		ila_crm_data(319 downto 315)	<= im_to_chipscope.im_ram_data_wr;
		ila_crm_data(399 downto 320)	<= (others => '0'); -- unsused bits
	end generate;
	RS8_RAM : if (region_size = 8) generate
		ila_crm_data(318 downto 310)	<= im_to_chipscope.im_ram_data_rd;
		ila_crm_data(327 downto 319)	<= im_to_chipscope.im_ram_data_wr;
		ila_crm_data(399 downto 328)	<= (others => '0'); -- unsused bits
	end generate;
	RS16_RAM : if (region_size = 16) generate
		ila_crm_data(326 downto 310)	<= im_to_chipscope.im_ram_data_rd;
		ila_crm_data(343 downto 327)	<= im_to_chipscope.im_ram_data_wr;
		ila_crm_data(399 downto 344)	<= (others => '0'); -- unsused bits
	end generate;

chipscope_ila : ila_icrm
	port map(
		clk => clkm,
		probe0 => ila_crm_data
	);
end generate;

crm_inv_man : entity icrm.invalidation_manager
    generic map(
	hindex => hindex_im,
	my_tile_id => my_tile_id,
	ioaddr => ioaddr_snoop,
	x_loc => x_loc,
	y_loc => y_loc,
        tech => tech_snoop
    )
    port map(
        clk => clkm,
        rst => rstn,
		ahbmi => ahbmi,
		ahbmo => ahbmo_chipscope,
        CStoIM => data_out_CStoIM,
		counters => counters,
		evictionPolicy => evictionPolicy,
		rd_en => rd_en,
        empty => empty,
        almost_full => almost_full_sig,
        r_addr => ram_addr,
        r_data_rd => ram_data_rd,
        r_data_wr => ram_data_wr,
        r_enable => ram_enable,
        r_write => ram_write,
        r_req => ram_req,
        r_gnt => ram_gnt,
        r_addr_snoop => ram_addr_snoop,
        r_data_rd_snoop => ram_data_rd_snoop,
        r_data_wr_snoop => ram_data_wr_snoop,
        r_enable_snoop => ram_enable_snoop,
        r_write_snoop => ram_write_snoop,
        r_req_snoop => ram_req_snoop,
        r_gnt_snoop => ram_gnt_snoop,
        im_to_chipscope => im_to_chipscope
    );

    fifo_connect : entity icrm.STD_FIFO_AF
    generic map(
        DATA_WIDTH => CStoIM_type_size,
		FIFO_DEPTH => 16384,	-- 65536 is the limit if 16 bits are used for FifoLevel
        CRITICAL_LEVEL => 1000,
        SAFE_LEVEL => 500
    )
    port map(
        clk => clkm,
        rst => rstn,
        WriteEn => wr_en,
        DataIn => data_in,
        ReadEn => rd_en,
        DataOut => data_out,
        Empty => empty,
        Full => full,
        Almost_full => almost_full_sig,
		FifoLevel => fifoLevel_sig,
        fifoDepth => fifoDepth_pos,
        fifoCriticalLevel => fifoCriticalLevel_pos,
        fifoSafeLevel => fifoSafeLevel_pos
    );

--    fifo_req : entity icrm.STD_FIFO
--    generic map(
--        DATA_WIDTH => 64,
--        FIFO_DEPTH => 32
--    )
--    port map(
--        clk => clkm,
--        rst => rstn,
--        WriteEn => req_wr_en,
--        DataIn => req_data_in,
--        ReadEn => req_rd_en,
--        DataOut => req_data_out,
--        Empty => req_empty,
--        Full => req_full
--    );

--    fifo_rsp : entity icrm.STD_FIFO
--    generic map(
--        DATA_WIDTH => 32,
--        FIFO_DEPTH => 32
--    )
--    port map(
--        clk => clkm,
--        rst => rstn,
--        WriteEn => rsp_wr_en,
--        DataIn => rsp_data_in,
--        ReadEn => rsp_rd_en,
--        DataOut => rsp_data_out,
--        Empty => rsp_empty,
--        Full => rsp_full
--    );

	crm_snoop : entity icrm.crm_snoop
    generic map(
        hindex => hindex_snoop,
        ioaddr => ioaddr_snoop,
        iomask => iomask_snoop,
        my_tile_id => my_tile_id,
		na_mst_rx_idx => na_mst_rx_idx
    )
    port map(
        rst => rstn,
        clk => clkm,
        ahbsi => ahbsi,
		ahbso => ahbso_chipscope,
        ahbmi => ahbmi,
        CStoIM => data_in_CStoIM,
		counters => counters,
		evictionPolicy => evictionPolicy,
        wr_en => wr_en,
        full => full,
        tile_src => tile_src,
        cc_wr_en => req_wr_en,
        cc_full => '0',--req_full,
        cc_data_req => req_data_in,
        cc_rd_en => rsp_rd_en,
        cc_empty => '1',--rsp_empty,
        cc_data_rsp => rsp_data_out,
        crm_en => crm_en,
        r_addr_snoop => ram_addr_snoop,
        r_data_rd_snoop => ram_data_rd_snoop,
        r_data_wr_snoop => ram_data_wr_snoop,
        r_enable_snoop => ram_enable_snoop,
        r_write_snoop => ram_write_snoop,
        r_req_snoop => ram_req_snoop,
        r_gnt_snoop => ram_gnt_snoop,
        fifoDepth => fifoDepth,
        fifoCriticalLevel => fifoCriticalLevel,
        fifoSafeLevel => fifoSafeLevel,
		fifoLevel => fifoLevel_sig,
		almostFull => almost_full_sig,
        cs_to_chipscope => cs_to_chipscope
    );

	ahbso <= ahbso_chipscope;
	ahbmo <= ahbmo_chipscope;

    data_in <= (data_in_CStoIM.tile_src & data_in_CStoIM.data & data_in_CStoIM.address) when wr_en = '1' else (others => '0');
    data_out_CStoIM.tile_src <= data_out((CStoIM_type_size-1) downto (CStoIM_type_size-1-dummy.tile_src'high));
    data_out_CStoIM.data <= data_out((CStoIM_type_size-1-dummy.tile_src'high)-1 downto 32);
    data_out_CStoIM.address <= data_out(31 downto 0);

    fifoDepth_pos <= to_integer(unsigned(fifoDepth));
    fifoCriticalLevel_pos <= to_integer(unsigned(fifoCriticalLevel));
    fifoSafeLevel_pos <= to_integer(unsigned(fifoSafeLevel));

    top_to_chipscope.top_wr_en <= wr_en;

--        crm_config : crm_config generic map(max_tile_cr => max_tile_cr)
--        port map (rstn, clkm, ram_addr, ram_data_rd, ram_data_wr, ram_enable, ram_write, ram_req, ram_gnt, req_rd_en, req_data_out, req_empty, rsp_wr_en, rsp_data_in, rsp_full);
end;
