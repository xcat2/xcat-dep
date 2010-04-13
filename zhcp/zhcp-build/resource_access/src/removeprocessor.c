// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#include "wrapperutils.h"

/**
 * Removes a processor to a virtual image's directory entry.
 *
 * @param $1: The name of the guest to which a processor is to be removed
 * @param $2: The virtual address of the processor which is to be removed
 *
 * @return 0 If the processor was successfully removed
 *         1 If given invalid parameters
 *         2 If the specified processor remains after attempted removal
 */
int main(int argC, char * argV[]) {

	if (argC != 3) {
		printf("Error: Wrong number of parameters");
		return 1;
	}

	char* image = argV[1];
	char* address = argV[2]; // Hexedecimal string, 00-3F

	printf("Removing processor %s on %s... ", address, image);

	VmApiInternalContext context;

	// Initialize context
	extern struct _smTrace externSmapiTraceFlags;
	smMemoryGroupContext memContext;
	memset(&context, 0, sizeof(context));
	memset(&memContext, 0, sizeof(memContext));
	memset(&externSmapiTraceFlags, 0, sizeof(smTrace));
	context.smTraceDetails = (struct _smTrace *) &externSmapiTraceFlags;
	context.memContext = &memContext;

	vmApiImageCpuDeleteDmOutput* output;

	int rc = smImage_CPU_Delete_DM(&context, "", 0, "", // Authorizing user, password length, password.
			image, address, &output);

	if (rc || (output->returnCode && output->returnCode != 520
			|| (output->reasonCode && output->reasonCode != 30))) {
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
