#include <stdint.h>
#include "xil_printf.h"
#include "xil_io.h"
#include "xparameters.h"
#include "profile_cnt.h"
#include "xgray_scale.h"
#include "xscugic.h"
// setting by myself
#define VDMA_GRAYSCALE XPAR_AXI_VDMA_0_BASEADDR

#define OV7670_STREAM XPAR_OV7670_DECODE_STREAM_0_0
#define VDMA_MM2S XPAR_VDMA_MM2S_BASEADDR
#define VDMA_S2MM XPAR_VDMA_S2MM_BASEADDR

#define VIDEO_RGB585_BASEADDR 0x02000000
#define VIDEO_RGB888_BASEADDR 0x03000000
#define PROC_VIDEO_BASEADDR 0x04000000

#define HEIGHT 480
#define WIDTH 640

/* Register offsets */
#define OFFSET_PARK_PTR_REG 0x28
#define OFFSET_VERSION 0x2c

#define OFFSET_VDMA_MM2S_CONTROL_REGISTER 0x00
#define OFFSET_VDMA_MM2S_STATUS_REGISTER 0x04
#define OFFSET_VDMA_MM2S_VSIZE 0x50
#define OFFSET_VDMA_MM2S_HSIZE 0x54
#define OFFSET_VDMA_MM2S_FRMDLY_STRIDE 0x58
#define OFFSET_VDMA_MM2S_FRAMEBUFFER1 0x5c
#define OFFSET_VDMA_MM2S_FRAMEBUFFER2 0x60
#define OFFSET_VDMA_MM2S_FRAMEBUFFER3 0x64
#define OFFSET_VDMA_MM2S_FRAMEBUFFER4 0x68

#define OFFSET_VDMA_S2MM_CONTROL_REGISTER 0x30
#define OFFSET_VDMA_S2MM_STATUS_REGISTER 0x34
#define OFFSET_VDMA_S2MM_IRQ_MASK 0x3c
#define OFFSET_VDMA_S2MM_REG_INDEX 0x44
#define OFFSET_VDMA_S2MM_VSIZE 0xa0
#define OFFSET_VDMA_S2MM_HSIZE 0xa4
#define OFFSET_VDMA_S2MM_FRMDLY_STRIDE 0xa8
#define OFFSET_VDMA_S2MM_FRAMEBUFFER1 0xac
#define OFFSET_VDMA_S2MM_FRAMEBUFFER2 0xb0
#define OFFSET_VDMA_S2MM_FRAMEBUFFER3 0xb4
#define OFFSET_VDMA_S2MM_FRAMEBUFFER4 0xb8

/* S2MM and MM2S control register flags */
#define VDMA_CONTROL_REGISTER_START 0x00000001
#define VDMA_CONTROL_REGISTER_CIRCULAR_PARK 0x00000002
#define VDMA_CONTROL_REGISTER_RESET 0x00000004
#define VDMA_CONTROL_REGISTER_GENLOCK_ENABLE 0x00000008
#define VDMA_CONTROL_REGISTER_FrameCntEn 0x00000010
#define VDMA_CONTROL_REGISTER_INTERNAL_GENLOCK 0x00000080
#define VDMA_CONTROL_REGISTER_WrPntr 0x00000f00
#define VDMA_CONTROL_REGISTER_FrmCtn_IrqEn 0x00001000
#define VDMA_CONTROL_REGISTER_DlyCnt_IrqEn 0x00002000
#define VDMA_CONTROL_REGISTER_ERR_IrqEn 0x00004000
#define VDMA_CONTROL_REGISTER_Repeat_En 0x00008000
#define VDMA_CONTROL_REGISTER_InterruptFrameCount 0x00ff0000
#define VDMA_CONTROL_REGISTER_IRQDelayCount 0xff000000

/* S2MM status register */
#define VDMA_STATUS_REGISTER_HALTED 0x00000001  // Read-only
#define VDMA_STATUS_REGISTER_VDMAInternalError \
  0x00000010                                             // Read or write-clear
#define VDMA_STATUS_REGISTER_VDMASlaveError 0x00000020   // Read-only
#define VDMA_STATUS_REGISTER_VDMADecodeError 0x00000040  // Read-only
#define VDMA_STATUS_REGISTER_StartOfFrameEarlyError 0x00000080  // Read-only
#define VDMA_STATUS_REGISTER_EndOfLineEarlyError 0x00000100     // Read-only
#define VDMA_STATUS_REGISTER_StartOfFrameLateError 0x00000800   // Read-only
#define VDMA_STATUS_REGISTER_FrameCountInterrupt 0x00001000     // Read-only
#define VDMA_STATUS_REGISTER_DelayCountInterrupt 0x00002000     // Read-only
#define VDMA_STATUS_REGISTER_ErrorInterrupt 0x00004000          // Read-only
#define VDMA_STATUS_REGISTER_EndOfLineLateError 0x00008000      // Read-only
#define VDMA_STATUS_REGISTER_FrameCount 0x00ff0000              // Read-only
#define VDMA_STATUS_REGISTER_DelayCount 0xff000000              // Read-only

typedef struct {
  unsigned int baseAddr;
  int width;
  int height;
  int pixelLength;
  int fbLength;
  volatile unsigned int *vdmaVirtualAddress;
  uint16_t *fb1PhysicalAddress;
} vdma_handle;

int vdma_setup(vdma_handle *handle, unsigned int baseAddr, int width,
               int height, int pixelLength, unsigned int fb1Addr) {
  handle->width = width;
  handle->height = height;
  handle->pixelLength = pixelLength;
  handle->fbLength = pixelLength * width * height;

  handle->vdmaVirtualAddress = (unsigned int *)baseAddr;
  handle->fb1PhysicalAddress = (uint16_t *)fb1Addr;
  return 0;
}

unsigned int vdma_get(vdma_handle *handle, int num) {
  return handle->vdmaVirtualAddress[num >> 2];
}

void vdma_set(vdma_handle *handle, int num, unsigned int val) {
  handle->vdmaVirtualAddress[num >> 2] = val;
}

void vdma_start_s2mm(vdma_handle *handle) {
  // Reset VDMA
  vdma_set(handle, OFFSET_VDMA_S2MM_CONTROL_REGISTER,
           VDMA_CONTROL_REGISTER_RESET);

  // Wait for reset to finish
  while ((vdma_get(handle, OFFSET_VDMA_S2MM_CONTROL_REGISTER) &
          VDMA_CONTROL_REGISTER_RESET) == 4)
    ;

  // Clear all error bits in status register
  vdma_set(handle, OFFSET_VDMA_S2MM_STATUS_REGISTER, 0);

  // Do not mask interrupts
  vdma_set(handle, OFFSET_VDMA_S2MM_IRQ_MASK, 0xf);

  int interrupt_frame_count = 1;

  // Start both S2MM and MM2S in triple buffering mode
  vdma_set(handle, OFFSET_VDMA_S2MM_CONTROL_REGISTER,
           (interrupt_frame_count << 16) | VDMA_CONTROL_REGISTER_START);

  while ((vdma_get(handle, 0x30) & 1) == 0 || (vdma_get(handle, 0x34) & 1) == 1)
    ;

  // Extra register index, use first 16 frame pointer registers
  vdma_set(handle, OFFSET_VDMA_S2MM_REG_INDEX, 0);

  // Write physical addresses to control register
  vdma_set(handle, OFFSET_VDMA_S2MM_FRAMEBUFFER1,
           (unsigned int)handle->fb1PhysicalAddress);

  // Write Park pointer register
  vdma_set(handle, OFFSET_PARK_PTR_REG, 0);

  // Frame delay and stride (bytes)
  vdma_set(handle, OFFSET_VDMA_S2MM_FRMDLY_STRIDE,
           handle->width * handle->pixelLength);

  // Write horizontal size (bytes)
  vdma_set(handle, OFFSET_VDMA_S2MM_HSIZE, handle->width * handle->pixelLength);

  // Write vertical size (lines), this actually starts the transfer
  vdma_set(handle, OFFSET_VDMA_S2MM_VSIZE, handle->height);
}

void vdma_start_mm2s(vdma_handle *handle) {
  // Reset VDMA
  vdma_set(handle, OFFSET_VDMA_MM2S_CONTROL_REGISTER,
           VDMA_CONTROL_REGISTER_RESET);

  // Wait for reset to finish
  while ((vdma_get(handle, OFFSET_VDMA_MM2S_CONTROL_REGISTER) &
          VDMA_CONTROL_REGISTER_RESET) == 4)
    ;

  // Clear all error bits in status register
  vdma_set(handle, OFFSET_VDMA_MM2S_STATUS_REGISTER, 0);

  int interrupt_frame_count = 1;

  // Set buffer number
  vdma_set(handle, OFFSET_VDMA_MM2S_CONTROL_REGISTER,
           (interrupt_frame_count << 16) | VDMA_CONTROL_REGISTER_START);

  vdma_set(handle, OFFSET_VDMA_MM2S_FRAMEBUFFER1,
           (unsigned int)handle->fb1PhysicalAddress);

  // Write Park pointer register
  vdma_set(handle, OFFSET_PARK_PTR_REG, 0);

  // Frame delay and stride (bytes)
  vdma_set(handle, OFFSET_VDMA_MM2S_FRMDLY_STRIDE,
           handle->width * handle->pixelLength);

  // Write horizontal size (bytes)
  vdma_set(handle, OFFSET_VDMA_MM2S_HSIZE, handle->width * handle->pixelLength);

  // Write vertical size (lines), this actually starts the transfer
  vdma_set(handle, OFFSET_VDMA_MM2S_VSIZE, handle->height);
}

void captureRaw(u32 src, u32 dst) {
	size_t offset1 = src;
	size_t offset2 = dst;
	for (size_t row = 0; row < WIDTH; ++row) {
	  for (size_t col = 0; col < HEIGHT; ++col) {
		u16 pixel = Xil_In16(offset1);
		u32 b = (u32) (pixel&0x1f);
		u32 g = (u32) ((pixel>>5) & 0x3f);
		u32 r = (u32) ((pixel>>11) & 0x1f);
		u32 pixel2 = (r<<19) | (g<<10) | (b<<3);
		Xil_Out32(offset2, pixel2);

		offset1 = offset1 + 2;
		offset2 = offset2 + 4;
	  }
	}
}



void Grayscale_ISR(void* InstancePtr) {
  // see Xilinx tutorial!!
  int enabled_list;
  int status_list;
  XGray_scale *grayscale_filter = (XGray_scale *)InstancePtr;
  XGray_scale_InterruptGlobalDisable(grayscale_filter);

  enabled_list = XGray_scale_InterruptGetEnabled(grayscale_filter);
  status_list = XGray_scale_InterruptGetStatus(grayscale_filter);

  init_perfcounters(1,0);
  EnablePerfCounters();
  u32 value2;

  if ((enabled_list & 1) && (status_list & 1)) {
	//xil_printf("interrupt acknowledged\n");
	XGray_scale_InterruptClear(grayscale_filter, 1);
	 u32 value = get_cyclecount();
	 double value3 = (value-value2)/(double)667000;
	 printf("grayscale cycle %f ms\r",value3);
	 value2 = value;
  }
  XGray_scale_InterruptGlobalEnable(grayscale_filter);
}

int setupInterrupt(XScuGic *interrupt_controller,
                   XGray_scale *grayscale_filter) {
  // See Xilinx tutorial!!
  int Status;
  XScuGic_Config *pCfg = XScuGic_LookupConfig(XPAR_SCUGIC_0_DEVICE_ID);
  Status =
      XScuGic_CfgInitialize(interrupt_controller, pCfg, pCfg->CpuBaseAddress);
  Xil_ExceptionInit();
  Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT,
                               (Xil_ExceptionHandler)XScuGic_InterruptHandler,
                               interrupt_controller);
  Xil_ExceptionEnable();
  Status = XScuGic_Connect(
      interrupt_controller, XPAR_FABRIC_GRAY_SCALE_0_INTERRUPT_INTR,
      (Xil_InterruptHandler)Grayscale_ISR, grayscale_filter);
  XScuGic_Enable(interrupt_controller, XPAR_FABRIC_GRAY_SCALE_0_INTERRUPT_INTR);

  return Status;
}
//void convToGray(u32 src, u32 dst) {
  // Enter your code here
//	size_t offset1 = src;
//	size_t offset2 = dst;
//		for (size_t row = 0; row < WIDTH; ++row) {
//		  for (size_t col = 0; col < HEIGHT; ++col) {
//			u32 pixel = Xil_In32(offset1);
//			u32 b = (u32) (pixel&0xff);
//			u32 g = (u32) ((pixel>>8) & 0xff);
//			u32 r = (u32) ((pixel>>16) & 0xff);
//			u32 tmp1 = (double)(r*0.299+g*0.587+b*0.114);
//			u32 tmp2 = tmp1 & 0xff;
//			u32 pixel2 = (tmp2<<16) | (tmp2<<8) | (tmp2);
//			Xil_Out32(offset2, pixel2);

//			offset1 = offset1 + 4;
//			offset2 = offset2 + 4;
//		  }
//		}
//}

int main() {
  vdma_handle handle_s2mm;
  vdma_handle handle_mm2s;
  /////////////////////////////////////////////////////////////////////////////////////
  XGray_scale grayscale_filter;
  int Status = XGray_scale_Initialize(&grayscale_filter,XPAR_GRAY_SCALE_0_DEVICE_ID);
  if(Status != XST_SUCCESS)
  {
	  xil_printf("GrayscaleIP is not initialized properly \r\n");
	  return XST_FAILURE;
  }
  XGray_scale_SetRows(&grayscale_filter,HEIGHT);
  XGray_scale_SetCols(&grayscale_filter,WIDTH);
  XGray_scale_EnableAutoRestart(&grayscale_filter);
  XGray_scale_Start(&grayscale_filter);
  // config Grayscale IP
  XGray_scale_InterruptGlobalEnable(&grayscale_filter);
  XGray_scale_InterruptEnable(&grayscale_filter,1);
  XScuGic interrupt_controller;
  Status = setupInterrupt(&interrupt_controller,&grayscale_filter);
  /////////////////////////////////////////////////////////////////////////////////////
  vdma_handle grayscale_vdma_handle_s2mm;
  vdma_handle grayscale_vdma_handle_mm2s;
  /////////////////////////////////////////////////////////////////////////////////////
  vdma_setup(&grayscale_vdma_handle_mm2s, VDMA_GRAYSCALE, WIDTH, HEIGHT, 4, VIDEO_RGB888_BASEADDR);
  vdma_setup(&grayscale_vdma_handle_s2mm, VDMA_GRAYSCALE, WIDTH, HEIGHT, 4, PROC_VIDEO_BASEADDR);
  /////////////////////////////////////////////////////////////////////////////////////
  // Setup VDMA handle and memory-mapped ranges
  vdma_setup(&handle_s2mm, VDMA_S2MM, WIDTH, HEIGHT, 2, VIDEO_RGB585_BASEADDR);
  vdma_setup(&handle_mm2s, VDMA_MM2S, WIDTH, HEIGHT, 4, PROC_VIDEO_BASEADDR);

  // Start triple buffering
  vdma_start_s2mm(&handle_s2mm);
  vdma_start_mm2s(&handle_mm2s);

  vdma_start_mm2s(&grayscale_vdma_handle_mm2s);
  vdma_start_s2mm(&grayscale_vdma_handle_s2mm);


  Xil_Out32(OV7670_STREAM, 1); 

  while (1) {
    captureRaw(VIDEO_RGB585_BASEADDR, VIDEO_RGB888_BASEADDR);

    //convToGray(VIDEO_RGB888_BASEADDR, PROC_VIDEO_BASEADDR);

      //  u32 value = get_cyclecount();
        //double value3 = (value-value2)/(double)667000;
      //  printf("grayscale cycle %f ms\r",value3);
       // value2 = value;
  }

  return 0;
}

