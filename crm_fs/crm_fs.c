#include <stdio.h>
#include "string.h"
#include "../../src/lib/test_functions.h"
#include "../../src/defines.h"
#include "../../src/hw/bootup.h"
#include "../../src/hw/icrm/icrm.h"
#include "../../src/hw/mm_registers.h"

#define MY_DELAY 0
//#define NUM_OF_CL 128
//#define WORDS_PER_CL 8
#define NUM_OF_CL 1
#define WORDS_PER_CL 1
#define TOTAL_WORDS (NUM_OF_CL*WORDS_PER_CL)
#define DIRTY_NUM 8
#define CHECKER_MASK 0xF00FFFFF
#define SEND_SIG_DATA_MASK 0x000AB111
#define RECEIVE_SIG_DATA_MASK 0x111AB000
#define DMA_LOOP 0
#define FFC_TRAFFIC 0
#define DMA_TYPE HWCIC // HWCPY HWCIC HWDMA

volatile unsigned int *addr0 = (volatile unsigned int *) 0x80000000;
volatile unsigned int *addr1 = (volatile unsigned int *) 0x80100000;
volatile unsigned int *addr2 = (volatile unsigned int *) 0x80200000;
volatile unsigned int *addr3 = (volatile unsigned int *) 0x80300000;
volatile unsigned int *addr4 = (volatile unsigned int *) 0x80400000;
volatile unsigned int *addr5 = (volatile unsigned int *) 0x80500000;
volatile unsigned int *addr6 = (volatile unsigned int *) 0x80600000;
volatile unsigned int *addr7 = (volatile unsigned int *) 0x80700000;

/*	############################
* 	Gaith function
* 	############################
*/
volatile unsigned int tile_mask[NTILE] = {1,1,1,1}; // Work in Progress -> Need to enable the for loops

struct iLet dummy_ilet = {(void*)0, (void*)0, 0, 0};

void local_checker(volatile unsigned int *addr, volatile unsigned int tileID)
{
	volatile unsigned int wr_data = (0xffff0000 & CHECKER_MASK) | (tileID << 24) | (tileID << 20);
	volatile unsigned int correct[WORDS_PER_CL] = {0};
	volatile unsigned int wrong[WORDS_PER_CL] = {0};
	volatile unsigned int i,j,k;

	for(i=0,j=0; i<NUM_OF_CL; i++,j+=WORDS_PER_CL)
	{
		for(k=0; k<DIRTY_NUM; k++)
		{
			if(*(addr+j+k) == wr_data + i + k)
				correct[k]++;
			else
				wrong[k]++;
		}
	}
}

void remote_checker(volatile unsigned int *addr, volatile unsigned int data)
{
	volatile unsigned int correct = 0;
	volatile unsigned int wrong = 0;
	volatile unsigned int i;

	for(i=0; i<TOTAL_WORDS; i++)
	{
		if(*toGlobal(addr+i,1) == data + i)
			correct++;
		else
			wrong++;
	}
}

int send_SignalData(volatile unsigned int tileID)
{
	return ((SEND_SIG_DATA_MASK) || (tileID << 28) || (tileID << 24) || (tileID << 20));
}

int receive_SignalData(volatile unsigned int tileID)
{
	return ((RECEIVE_SIG_DATA_MASK) || (tileID << 8) || (tileID << 4) || (tileID));

}
/*	############################
* 	Gaith function
* 	############################
*/
int main()
{
	bootup_routine(0xf);
	    volatile unsigned int *addr = addr2;/* 0x80200000*/
		volatile unsigned int *addr1 = addr5;/* 0x80500000*/

	/*	############################
	* 	Put test function below here
	* 	############################
	*/

		/*if(get_coreid() == 1)
    {
        volatile unsigned int l2c_bug = *toGlobal(addr4,((*tile_id)+1)%4);
        l2c_bug++;

		if(get_tileid() == 0)   // TILE 0 //
        {
			volatile unsigned int a;
			*addr_0 = 0xabcdabca; // 0x80200000//
			a = *(addr_0);
		}


		if(get_tileid() == 0)   // TILE 1 //
		{
				volatile unsigned int b;
				*addr_0 = 0xdcbadcba; // 0x80300000 //
				b = *(addr_0);

		}
	}*/
	if(get_coreid() == 1)
	{
		volatile unsigned int l2c_bug = *toGlobal(addr4,((*tile_id)+1)%4);
		l2c_bug++;

		    if(get_tileid() == 0 && tile_mask[get_tileid()])   /* TILE 0 */
			{
				volatile unsigned int i,j,k,a;

				pull_signal_local(1,0x000ab111);

				for(i=0,j=0; i<NUM_OF_CL; i++,j+=WORDS_PER_CL)
				{
					for(k=0; k<DIRTY_NUM; k++) /* dirty num = 8 */
					{
						a = (*toGlobal(addr+j+k,1));
					}
				}

				signal_remote(1,0,0x111ab000); /* dst_tile ,id ,val)*/

				pull_signal_local(1,0x000ab111);

				remote_checker(addr,0x01100000);

				signal_remote(1,0,0x111ab000);

				pull_signal_local(1,0x000ab111);

				for(i=0,j=0; i<NUM_OF_CL; i++,j+=WORDS_PER_CL)
				{
					for(k=0; k<DIRTY_NUM; k++)
					{
						(*toGlobal(addr+j+k,1)) = 0xf00f0000 + i + k;
					}
				}

				signal_remote(1,0,0x111ab000);

				pull_signal_local(1,0x000ab111);

				remote_checker(addr,0x11110000);

			}

			if (get_tileid() == 1 && tile_mask[get_tileid()])  /* TILE 1 */
			{
				volatile unsigned int a,i,j,k;

				// Signal to Read
				signal_remote(0,1,0x000ab111);      // (DstTileID, SignalBlockID.SrcTileID, Data); Data = DstTileID ab SignalBlockID
				signal_remote(2,1,0x222ab111);

				// Poll after Reading (Local ST is updated)
				pull_signal_local(0,0x111ab000);    // (SignalBlockID, Data); Data = LocalTileID ab SignalingTileID
				pull_signal_local(2,0x111ab222);


				// Re-write to trigger INVs
				for(i=0; i<TOTAL_WORDS;i++)
					*(addr+i) = 0x01100000+i;

				for(i=0; i<TOTAL_WORDS;i++)
					*(addr1+i) = 0x01100000+i;

				// Signal to Re-read (as data is invalidated)
				signal_remote(0,1,0x000ab111);
				signal_remote(2,1,0x222ab111);

				// Poll after Re-reading (Local ST is updated)
				pull_signal_local(0,0x111ab000);
				pull_signal_local(2,0x111ab222);

				// Signal to Trigger Individual WBs
				signal_remote(0,1,0x000ab111);
				pull_signal_local(0,0x111ab000);
				local_checker(addr,0);

				// Signal to Trigger Individual WBs
				signal_remote(2,1,0x222ab111);
				pull_signal_local(2,0x111ab222);
				local_checker(addr,2);

				// Re-write to trigger INVs
				for(i=0; i<TOTAL_WORDS;i++)
					*(addr+i) = 0x11110000+i;

				// Signal to Re-read (as data is invalidated)
				signal_remote(0,1,0x000ab111);
				signal_remote(2,1,0x222ab111);
				/**/
			}

			if (*tile_id == 2 && tile_mask[get_tileid()])  /* TILE 2 */
			{
				volatile unsigned int i,j,k,a;

				pull_signal_local(1,0x222ab111);

				for(i=0,j=0; i<NUM_OF_CL; i++,j+=WORDS_PER_CL)
				{
					for(k=0; k<DIRTY_NUM; k++)
					{
						a = (*toGlobal(addr1+j+k,1));
					}
				}

				signal_remote(1,2,0x111ab222);

				pull_signal_local(1,0x222ab111);

				remote_checker(addr1,0x01100000);

				signal_remote(1,2,0x111ab222);

				pull_signal_local(1,0x222ab111);

				for(i=0,j=0; i<NUM_OF_CL; i++,j+=WORDS_PER_CL)
				{
					for(k=0; k<DIRTY_NUM; k++)
					{
						(*toGlobal(addr1+j+k,1)) = 0xf22f0000 + i + k;
					}
				}

				signal_remote(1,2,0x111ab222);

				pull_signal_local(1,0x222ab111);

				remote_checker(addr1,0x11110000);
			}

	    }




	/*	############################
	* 	Put test function above here
	* 	############################
	*/

	shutdown_routine();

}

