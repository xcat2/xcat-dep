// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#ifndef _VMAPI_CHECK_AUTHENTICATION_H
#define _VMAPI_CHECK_AUTHENTICATION_H
#include "smPublic.h"
#include "smapiTableParser.h"
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Check_Authentication
typedef commonOutputFields vmApiCheckAuthenticationOutput;

// Parser table for Check_Authentication
static tableLayout Check_Authentication_Layout = { { APITYPE_BASE_STRUCT_LEN,
		4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiCheckAuthenticationOutput) }, { APITYPE_INT4, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, offsetof(vmApiCheckAuthenticationOutput,
				requestId) }, { APITYPE_INT4, 4, 4, STRUCT_INDX_0,
		NEST_LEVEL_0, offsetof(vmApiCheckAuthenticationOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiCheckAuthenticationOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int smCheck_Authentication(struct _VmApiInternalContext* vmapiContextP,
		char * userid, int passwordLength, char * password,
		vmApiCheckAuthenticationOutput ** outData);

#ifdef __cplusplus
}
#endif

#endif
