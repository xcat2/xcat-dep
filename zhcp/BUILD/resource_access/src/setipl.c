// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#include "wrapperutils.h"

/**
 * Sets the IPL statement for the z/VM guest with the specified name.
 *
 * @param $1: The name of the guest for which the IPL statement is to be set.
 * @param $2: The new IPL statement's IPL target string.
 * @param $3: The new IPL statement's load parameter string.
 * @param $4: The new IPL statement's parameter string.
 *
 * @return 0 If the virtual image now exists
 *         1 If given invalid parameters
 *         2 If image creation failed
 */
int main(int argC, char * argV[]) {

	if (argC != 5) {
		printf("Error: Wrong number of parameters\n");
		return 1;
	}

	char* image = argV[1];
	char* ipltarget = argV[2];
	char* loadparms = argV[3];
	char* parms = argV[4];

	// Check if the userID is between 1 and 8 characters
	if (isImageNameInvalid(image))
		return 1;

	printf("Setting IPL statement on %s... ", image);

	VmApiInternalContext context;

	// Initialize context
	extern struct _smTrace externSmapiTraceFlags;
	smMemoryGroupContext memContext;
	memset(&context, 0, sizeof(context));
	memset(&memContext, 0, sizeof(memContext));
	memset(&externSmapiTraceFlags, 0, sizeof(smTrace));
	context.smTraceDetails = (struct _smTrace *) &externSmapiTraceFlags;
	context.memContext = &memContext;

	vmApiImageIplSetDmOutput* output;

	int rc = smImage_IPL_Set_DM(&context, "", 0, "", // Authorizing user, password length, password.
			image, ipltarget, loadparms, parms, &output);

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
