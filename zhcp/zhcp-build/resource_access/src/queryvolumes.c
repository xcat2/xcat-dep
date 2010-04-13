// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#include "wrapperutils.h"

/**
 * Prints out information about disk spaces on a z/VM system.
 *
 * @param $1: The type of query to run
 * @param $2: The type of space to query
 *
 * @return 0 If the virtual image was created
 *         1 If given invalid parameters
 *         2 If the image name list could not be retrieved
 */
int main(int argC, char * argV[]) {

	if (argC != 3) {
		printf("Error: Wrong number of parameters\n");
		return 1;
	}

	char* queryType = argV[1];
	char* entryType = argV[2];

	int iQueryType;
	if (!strcmp(queryType, "definition")) {
		iQueryType = 1;
	} else if (!strcmp(queryType, "free")) {
		iQueryType = 2;
	} else if (!strcmp(queryType, "used")) {
		iQueryType = 3;
	} else {
		return 1;
	}

	int iEntryType;
	if (!strcmp(entryType, "volume")) {
		iEntryType = 1;
	} else if (!strcmp(entryType, "region")) {
		iEntryType = 2;
	} else if (!strcmp(entryType, "group")) {
		iEntryType = 3;
	} else {
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

	vmApiImageVolumeSpaceQueryDmOutput* output;

	int rc = smImage_Volume_Space_Query_DM(&context, "", 0, "", // Authorizing user, password length, password.
			"NA", // Doesn't matter what image name we use.
			iQueryType, iEntryType, "*", // List all spaces of specified type.
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
		int i, l;
		int n = output->recordCount;
		int p = 0;
		for (i = 0; i < n; i++) {
			l = output->recordList[i].imageRecordLength;
			printf("%.*s\n", l, output->recordList[0].imageRecord + p);
			p = p + l;
		}

		// Release context
		smMemoryGroupFreeAll(&context);
		smMemoryGroupTerminate(&context);

		return 0;
	}
}
