// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#include "wrapperutils.h"

/**
 * Prints out the specified profile.
 *
 * @param $1: The name of the profile which is to be listed
 *
 * @return 0 If the profile was successfully printed
 *         1 If given invalid parameters
 *         2 If the profile could not be retrieved
 */
int main(int argC, char * argV[]) {

	if (argC != 2) {
		printf("Error: Wrong number of parameters\n");
		return 1;
	}

	// Image name
	char * profile = argV[1];

	VmApiInternalContext context;

	// Initialize context
	extern struct _smTrace externSmapiTraceFlags;
	smMemoryGroupContext memContext;
	memset(&context, 0, sizeof(context));
	memset(&memContext, 0, sizeof(memContext));
	memset(&externSmapiTraceFlags, 0, sizeof(smTrace));
	context.smTraceDetails = (struct _smTrace *) &externSmapiTraceFlags;
	context.memContext = &memContext;

	vmApiProfileQueryDmOutput * output;

	// Query DirMaint profile
	int rc = smProfile_Query_DM(&context, "", // Authorizing user
			0, // Password length
			"", // Password
			profile,// Profile name
			&output);

	if (rc || output->common.returnCode || output->common.reasonCode) {
		printf("Failed\n");

		rc ? printf("  Return code: %d\n", rc) : printf("  Return code: %d\n"
			"  Reason code: %d\n", output->common.returnCode,
				output->common.reasonCode);

		// Release context
		smMemoryGroupFreeAll(&context);
		smMemoryGroupTerminate(&context);

		return 2;
	} else {
		// Print out DirMaint directory entry
		int i;
		int recCount = output->profileRecordCount;
		int recLen = 72;

		// Line to print
		char line[recLen], chs[4];

		if (recCount > 0) {
			// Loop through image record and print out directory entry
			for (i = 0; i < recCount; i++) {
				memset(line, 0, recLen);
				memcpy(line, output->profileRecordList[i].recordData, recLen);

				// Print lines that are not comment
				trim(line);

				// Copy first 4 characters
				strncpy(chs, line, 4);

				// If first 4 characters does not have * (comment)
				if (!strstr(chs, "*")) {
					printf("%s\n", line);
				}
			} // End of for
		}
	} // End of else

	// Release context
	smMemoryGroupFreeAll(&context);
	smMemoryGroupTerminate(&context);

	return 0;
}
