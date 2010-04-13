// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#include "wrapperutils.h"

/**
 * Adds a 3390 (ECKD) disk to a virtual image's directory entry.
 *
 * @param $1: The name of the guest to which a disk is to be added
 * @param $2: The name of the disk pool from which a disk is to be allocated
 * @param $3: The virtual device address for the newly-allocated volume
 * @param $4: The mode under which the disk is to be linked by the user
 * @param $5: The size of the new disk, in cylinders
 * @param $6: The read password
 * @param $7: The write password
 * @param $8: The multi password
 *
 * @return 0 If the disk was added successfully
 *         1 If given invalid parameters
 *         2 If disk allocation failed
 */
int main(int argC, char* argV[]) {

	if (argC < 6 || argC > 9) {
		printf("Error: Wrong number of parameters\n");
		return 1;
	}

	char* image = argV[1];
	char* pool = argV[2];
	char* vdev = argV[3];
	int size = atoi(argV[4]);
	char* mode = argV[5];

	// Read password
	char* readPw = "";
	if (argC > 7 && argV[6])
		readPw = argV[6];

	// Write password
	char* writePw = "";
	if (argC > 8 && argV[7])
		writePw = argV[7];

	// Mutli password
	// In order to link to a disk, a multi password must be specified
	char* multiPw = "";
	if (argC > 9 && argV[8])
		multiPw = argV[8];

	// Check if the userID is between 1 and 8 characters
	if (isImageNameInvalid(image))
		return 1;

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
			image, vdev, "3390", "AUTOG", pool, 1, // Cylinders
			size, mode, 1, "", // Do not format disk. Do not give disk a label.
			readPw, writePw, multiPw, // Read, write, and multi passwords.
			&output);

	if (rc || (output->common.returnCode && output->common.returnCode != 408
			&& output->common.returnCode != 592)
			|| (output->common.reasonCode && output->common.reasonCode != 4
					&& output->common.reasonCode != 0)) {
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
