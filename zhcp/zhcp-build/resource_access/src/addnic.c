// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#include <string.h>
#include "vmapiVirtual.h"
#include "wrapperutils.h"

/**
 * Adds a network adapter to a virtual image's directory entry.
 *
 * @param $1: The z/VM guest for which a NIC is being allocated
 * @param $2: The virtual device address of the NIC being allocated
 * @param $3: The type of NIC which is to be allocated
 * @param $4: The number of VDEV channels associated with this NIC
 *
 * @return 0 If the NIC was added successfully
 *         1 If given invalid parameters
 *         2 If the NIC definition failed
 */
int main(int argC, char * argV[]) {

	if (argC != 5) {
		printf("Error: Wrong number of parameters");
		return 1;
	}

	char* image = argV[1];
	char* address = argV[2];
	char* type = argV[3];
	int devcount = atoi(argV[4]);

	// Check if the userID is between 1 and 8 characters
	if (isImageNameInvalid(image))
		return 1;

	int typecode;
	if (!strcmp(type, "HiperSockets")) {
		typecode = 1;
	} else if (!strcmp(type, "QDIO")) {
		typecode = 2;
	} else {
		printf("Error: NIC type must be HiperSockets or QDIO\n");
		return 1;
	}

	printf("Adding NIC %s to %s... ", address, image);

	VmApiInternalContext context;

	// Initialize context
	extern struct _smTrace externSmapiTraceFlags;
	smMemoryGroupContext memContext;
	memset(&context, 0, sizeof(context));
	memset(&memContext, 0, sizeof(memContext));
	memset(&externSmapiTraceFlags, 0, sizeof(smTrace));
	context.smTraceDetails = (struct _smTrace *) &externSmapiTraceFlags;
	context.memContext = &memContext;

	vmApiVirtualNetworkAdapterCreateDmOutput* output;

	int rc = smVirtual_Network_Adapter_Create_DM(&context, "", 0, "", // Authorizing user, password length, password.
			image, address, typecode, devcount, "", // Only relevant for a second-level z/OS.
			"", // The MAC identifier.
			&output);

	if (rc || output->returnCode || output->reasonCode) {
		printf("Failed\n");

		rc ? printf("  Return Code: %d\n", rc) : printf("  Return Code: %d\n"
			"  Reason Code: %d\n", output->returnCode, output->reasonCode);

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
