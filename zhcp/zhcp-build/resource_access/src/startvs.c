// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#include "wrapperutils.h"

/**
 * Logs on the specified virtual server.
 *
 * @param $1: The name of the guest which is to be logged on
 *
 * @return 0 If the image is powered on upon completion
 *         1 If given invalid parameters
 *         2 If power-on failed
 */
int main(int argC, char* argV[]) {

	if (argC != 2) {
		printf("Error: Wrong number of parameters\n");
		return 1;
	}

	// Get the virtual server name
	char* imageName = argV[1];
	// Check if the virtual server name is between 1 and 8 characters
	if (isImageNameInvalid(imageName))
		return 1;

	printf("Starting %s... ", imageName);

	VmApiInternalContext context;

	// Initialize context
	extern struct _smTrace externSmapiTraceFlags;
	smMemoryGroupContext memContext;
	memset(&context, 0, sizeof(context));
	memset(&memContext, 0, sizeof(memContext));
	memset(&externSmapiTraceFlags, 0, sizeof(smTrace));
	context.smTraceDetails = (struct _smTrace *) &externSmapiTraceFlags;
	context.memContext = &memContext;

	vmApiImageActivateOutput* output;

	// Log on virtual server
	int rc = smImage_Activate(&context, "", 0, "", // Authorizing user, password length, password.
			imageName, // Image name.
			&output);

	int rtnCode = output->common.returnCode;
	int rsnCode = output->common.reasonCode;

	// If return code = 200 and reason code = 8, virtual server is logged on
	if (rc || (output->common.returnCode && output->common.returnCode != 200
			|| (output->common.reasonCode && output->common.reasonCode != 8))) {
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
