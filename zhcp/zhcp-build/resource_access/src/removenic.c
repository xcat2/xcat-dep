// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#include <string.h>
#include "vmapiVirtual.h"
#include "wrapperutils.h"

/**
 * Removes a network adapter from a virtual image's directory entry.
 *
 * @param $1: The z/VM guest from which the NIC is to be removed
 * @param $2: The virtual device address of the NIC which is to be removed
 *
 * @return 0 If the NIC was removed successfully
 *         1 If given invalid parameters
 *         2 If the NIC removal failed
 */
int main(int argC, char * argV[]) {

	if (argC != 3) {
		printf("Error: Wrong number of parameters\n");
		return 1;
	}

	char* image = argV[1];
	char* address = argV[2];

	if (isImageNameInvalid(image))
		return 1;

	printf("Removing NIC %s on %s... ", address, image);

	VmApiInternalContext context;

	// Initialize context
	extern struct _smTrace externSmapiTraceFlags;
	smMemoryGroupContext memContext;
	memset(&context, 0, sizeof(context));
	memset(&memContext, 0, sizeof(memContext));
	memset(&externSmapiTraceFlags, 0, sizeof(smTrace));
	context.smTraceDetails = (struct _smTrace *) &externSmapiTraceFlags;
	context.memContext = &memContext;

	vmApiVirtualNetworkAdapterDeleteDmOutput* output;

	int rc = smVirtual_Network_Adapter_Delete_DM(&context, "", 0, "", // Authorizing user, password length, password.
			image, address, &output);

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
