// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#include "wrapperutils.h"

/**
 * Adds a non-dedicated processor to a virtual image's directory entry.
 *
 * @param $1: The z/VM guest to which a processor is to be added
 * @param $2: The virtual device address for the processor being added
 *
 * @return 0 If the processor was created
 *         1 If given invalid parameters
 *         2 If the processor definition failed
 */
int main(int argC, char * argV[]) {

	if (argC != 3) {
		printf("Error: Wrong number of parameters\n");
		return 1;
	}

	char* image = argV[1];
	char* address = argV[2]; // Hexedecimal string, 00-3F

	printf("Adding processor %s to %s... ", address, image);

	VmApiInternalContext context;

	// Initialize context
	extern struct _smTrace externSmapiTraceFlags;
	smMemoryGroupContext memContext;
	memset(&context, 0, sizeof(context));
	memset(&memContext, 0, sizeof(memContext));
	memset(&externSmapiTraceFlags, 0, sizeof(smTrace));
	context.smTraceDetails = (struct _smTrace *) &externSmapiTraceFlags;
	context.memContext = &memContext;

	vmApiImageCpuDefineDmOutput* output;

	int rc = smImage_CPU_Define_DM(&context, "", 0, "", // Authorizing user, password length, password.
			image, address, 0, // Base CPU status unspecified.
			"", // The processor identification number.
			1, // Not a dedicated processor.
			0, // Do not specify a cryptographic facility.
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
