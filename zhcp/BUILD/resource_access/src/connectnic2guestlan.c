// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#include "vmapiVirtual.h"
#include "wrapperutils.h"

/**
 * Connect network adapter to a GuestLAN.
 *
 * @param $1: The user for which a NIC is being connected
 * @param $2: The virtual device address of the NIC being connected
 * @param $3: The name of the LAN to which the NIC is to be connected
 * @param $4: The virtual image owning the GuestLAN segment to be connected
 *
 * @return 0 If the NIC was added successfully
 *         1 If given invalid parameters
 *         2 If the NIC could not be connected to the VSwitch
 */
int main(int argC, char * argV[]) {

	if (argC != 5) {
		printf("Error: Wrong number of parameters\n");
		return 1;
	}

	char* image = argV[1];
	char* address = argV[2];
	char* lan = argV[3];
	char* owner = argV[4];

	// Check if the userID is between 1 and 8 characters
	if (isImageNameInvalid(image) || isImageNameInvalid(owner))
		return 1;

	printf("Connecting NIC %s to GuestLan %s on %s... ", address, lan, image);

	VmApiInternalContext context;

	// Initialize context
	extern struct _smTrace externSmapiTraceFlags;
	smMemoryGroupContext memContext;
	memset(&context, 0, sizeof(context));
	memset(&memContext, 0, sizeof(memContext));
	memset(&externSmapiTraceFlags, 0, sizeof(smTrace));
	context.smTraceDetails = (struct _smTrace *) &externSmapiTraceFlags;
	context.memContext = &memContext;

	vmApiVirtualNetworkAdapterConnectVswitchDmOutput* output;

	int rc = smVirtual_Network_Adapter_Connect_LAN_DM(&context, "", 0, "",
			image, address, lan, owner, &output);

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
