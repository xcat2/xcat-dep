// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#include "wrapperutils.h"

/**
 * Adds a 9336 (FBA) disk to a virtual image's directory entry.
 *
 * @param $1: The name of the guest to which a disk is to be added
 * @param $2: The name of the disk pool from which a disk is to be allocated
 * @param $3: The virtual device address for the newly-allocated volume
 * @param $4: The mode under which the disk is to be linked by the user
 * @param $5: Block size (512, 1024, 2048, or 4096)
 * @param $6: The size of the new disk, in blocks
 * @param $7: The read password
 * @param $8: The write password
 * @param $9: The multi password
 *
 * @return 0 If the disk was added successfully
 *         1 If given invalid parameters
 *         2 If disk allocation failed
 */
int main(int argC, char* argV[]) {

	if (argC < 7 || argC > 10) {
		printf("Error: Wrong number of parameters\n");
		return 1;
	}

	char* image = argV[1];
	char* pool = argV[2];
	char* vdev = argV[3];
	char* mode = argV[4];
	int blocksize = atoi(argV[5]);
	int size = atoi(argV[6]);

	// Read password
	char* readPw = "";
	if (argC > 8 && argV[7])
		readPw = argV[7];

	// Write password
	char* writePw = "";
	if (argC > 9 && argV[8])
		writePw = argV[8];

	// Mutli password
	// In order to link to a disk, a multi password must be specified
	char* multiPw = "";
	if (argC > 10 && argV[9])
		multiPw = argV[9];

	// Check if the userID is between 1 and 8 characters
	if (isImageNameInvalid(image))
		return 1;

	int unit;
	switch (blocksize) {
	case 512:
		unit = 2;
		break;
	case 1024:
		unit = 3;
		break;
	case 2048:
		unit = 4;
		break;
	case 4096:
		unit = 5;
		break;
	default:
		printf("Error: Block size must be 512, 1024, 2048, or 4096\n");
		return 1;
	}

	printf("Adding disk %s to %s... ", vdev, image);

	VmApiInternalContext context;

	// Initialize context
	extern struct _smTrace externSmapiTraceFlags;
	smMemoryGroupContext memContext;
	memset(&context, 0, sizeof(context));
	memset(&memContext, 0, sizeof(memContext));
	memset(&externSmapiTraceFlags, 0, sizeof(smTrace));
	context.smTraceDetails = (struct _smTrace *) &externSmapiTraceFlags;
	context.memContext = &memContext;

	vmApiImageDiskCreateDmOutput* output;

	int rc = smImage_Disk_Create_DM(&context, "", 0, "", // Authorizing user, password length, password.
			image, vdev, "9336", "AUTOG", pool, unit, size, mode, 1, "", // Do not format disk.  Do not give disk a label.
			readPw, writePw, multiPw, // Read, write, and multi passwords.
			&output);

	if (rc || output->common.returnCode || output->common.reasonCode) {
		printf("Failed\n");

		rc ? printf("  Return Code: %d\n", rc) : printf("  Return Code: %d\n"
			"  Reason Code: %d\n", output->common.returnCode,
				output->common.reasonCode);

		// Release context
		smMemoryGroupFreeAll(&context);
		smMemoryGroupTerminate(&context);

		return 2;
	} else {
		printf("Done\n");

		// Release context
		smMemoryGroupFreeAll(&context);
		smMemoryGroupTerminate(&context);

		return 0;
	}
}
