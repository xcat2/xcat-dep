// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#include "wrapperutils.h"

/**
 * Prints out the specified DirMaint directory entry.
 *
 * @param $1: The name of the z/VM guest which is to be listed
 *
 * @return 0 If the image record was successfully printed
 *         1 If given invalid parameters
 *         2 If the image could not be retrieved
 */
int main(int argC, char * argV[]) {

	if (argC != 2) {
		printf("Error: Wrong number of parameters\n");
		return 1;
	}

	// Image name
	char * image = argV[1];

	VmApiInternalContext context;

	// Initialize context
	extern struct _smTrace externSmapiTraceFlags;
	smMemoryGroupContext memContext;
	memset(&context, 0, sizeof(context));
	memset(&memContext, 0, sizeof(memContext));
	memset(&externSmapiTraceFlags, 0, sizeof(smTrace));
	context.smTraceDetails = (struct _smTrace *) &externSmapiTraceFlags;
	context.memContext = &memContext;

	vmApiImageQueryDmOutput * output;

	// Query DirMaint directory entry
	int rc = smImage_Query_DM(&context, "", 0, "", image, &output, false);

	// Handle return code and reason code
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
		int recCount = output->imageRecordCount;
		int recLen = output->imageRecordList[0].imageRecordLength - 8;

		// Line to print
		char line[recLen], chs[4];

		if (recCount > 0) {
			int i;
			int token = 0;

			// Loop through image record and print out directory entry
			for (i = 0; i < recCount; i++) {
				memset(line, 0, recLen);
				memcpy(line, output->imageRecordList[i].imageRecord, recLen);

				// Print lines that are not comment
				trim(line);

				// Copy first 4 characters
				strncpy(chs, line, 4);

				// If first 4 characters does not have * (comment)
				if (!strstr(chs, "*")) {
					// Print directory entry line
					printf("%s\n", line);
				}
			}
		}

		// Release context
		smMemoryGroupFreeAll(&context);
		smMemoryGroupTerminate(&context);

		return 0;
	}
}
