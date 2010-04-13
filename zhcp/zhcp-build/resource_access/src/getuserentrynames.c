// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#include <stdlib.h>
#include "wrapperutils.h"

/**
 * Prints out a list of defined image names on a z/VM system.
 *
 * @return 0 If the list of image names was successfully printed
 *         1 If given invalid parameters
 *         2 If the image name list could not be retrieved
 */
int main(int argC, char * argV[]) {

	if (argC > 1) {
		printf("Error: Wrong number of parameters\n");
		return 1;
	}

	VmApiInternalContext context;

	// Initialize context
	extern struct _smTrace externSmapiTraceFlags;
	smMemoryGroupContext memContext;
	memset(&context, 0, sizeof(context));
	memset(&memContext, 0, sizeof(memContext));
	memset(&externSmapiTraceFlags, 0, sizeof(smTrace));
	context.smTraceDetails = (struct _smTrace *) &externSmapiTraceFlags;
	context.memContext = &memContext;

	vmApiImageNameQueryDmOutput* output;

	int rc = smImage_Name_Query_DM(&context, "", 0, "", // Authorizing user, password length, password.
			"NA", // Doesn't matter what image name we use.
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
		int i;
		int n = output->nameCount;
		for (i = 0; i < n; i++) {
			printf("%s\n", output->nameList[i]);
		}

		// Release context
		smMemoryGroupFreeAll(&context);
		smMemoryGroupTerminate(&context);

		return 0;
	}
}
