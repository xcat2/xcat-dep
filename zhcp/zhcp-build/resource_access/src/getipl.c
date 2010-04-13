// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#include "wrapperutils.h"

/**
 * Prints out the specified DirMaint profile entry.
 *
 * @param $1: The name of the profile which is to be listed
 *
 * @return 0 If the IPL entry was successfully printed
 *         1 If given invalid parameters
 *         2 If the IPL entry could not be retrieved
 */
int main(int argC, char * argV[]) {

	if (argC != 2) {
		printf("Error: Wrong number of parameters\n");
		return 1;
	}

	char* image = argV[1];

	VmApiInternalContext context;

	// Initialize context
	extern struct _smTrace externSmapiTraceFlags;
	smMemoryGroupContext memContext;
	memset(&context, 0, sizeof(context));
	memset(&memContext, 0, sizeof(memContext));
	memset(&externSmapiTraceFlags, 0, sizeof(smTrace));
	context.smTraceDetails = (struct _smTrace *) &externSmapiTraceFlags;
	context.memContext = &memContext;

	vmApiImageIplQueryDmOutput* output;

	int rc = smImage_IPL_Query_DM(&context, "", 0, "", // Authorizing user, password length, password.
			image, &output);

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
		printf("IPL target: %s\n"
			"LoadParms: %s\n"
			"Parameters: %s\n", output->savedSystem, output->loadParameter,
				output->parameters);

		// Release context
		smMemoryGroupFreeAll(&context);
		smMemoryGroupTerminate(&context);

		return 0;
	}
}
