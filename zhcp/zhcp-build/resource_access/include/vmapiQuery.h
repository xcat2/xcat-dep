// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#ifndef _VMAPI_QUERY_H
#define _VMAPI_QUERY_H
#include "smPublic.h"
#include "smapiTableParser.h"
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Query_API_Functional_Level
typedef commonOutputFields vmApiQueryApiFunctionalLevelOutput;

int smQuery_API_Functional_Level(struct _VmApiInternalContext* vmapiContextP,
		char * userid, int passwordLength, char * password,
		char * targetIdentifier, vmApiQueryApiFunctionalLevelOutput ** outData);

// Parser table for Query_API_Functional_Level
static tableLayout Query_API_Functional_Level_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiQueryApiFunctionalLevelOutput) }, { APITYPE_INT4, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiQueryApiFunctionalLevelOutput, requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiQueryApiFunctionalLevelOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiQueryApiFunctionalLevelOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };

// Query_Asychronous_Operation_DM
typedef commonOutputFields vmApiQueryAsynchronousOperationDmOutput;

int smQuery_Asychronous_Operation_DM(
		struct _VmApiInternalContext* vmapiContextP, char * userid,
		int passwordLength, char * password, char * targetIdentifier,
		int operationId, vmApiQueryAsynchronousOperationDmOutput ** outData);

// Parser table for Query_Asychronous_Operation_DM
static tableLayout Query_Asynchronous_Operation_DM_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiQueryAsynchronousOperationDmOutput) }, { APITYPE_INT4, 4,
		4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiQueryAsynchronousOperationDmOutput, requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiQueryAsynchronousOperationDmOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiQueryAsynchronousOperationDmOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };

// Query_Directory_Manager_Level_DM
typedef struct _vmApiQueryDirectoryManagerLevelDm {
	commonOutputFields common;
	char * directoryManagerLevel;
	int directoryManagerLevelLength;
} vmApiQueryDirectoryManagerLevelDmOutput;

// Parser table for Query_Directory_Manager_Level_DM
static tableLayout
		Query_Directory_Manager_Level_DM_Layout = { { APITYPE_BASE_STRUCT_LEN,
				4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
				sizeof(vmApiQueryDirectoryManagerLevelDmOutput) }, {
				APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
						vmApiQueryDirectoryManagerLevelDmOutput,
						common.requestId) }, { APITYPE_INT4, 4, 4,
				STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
						vmApiQueryDirectoryManagerLevelDmOutput,
						common.returnCode) }, { APITYPE_INT4, 4, 4,
				STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
						vmApiQueryDirectoryManagerLevelDmOutput,
						common.reasonCode) }, { APITYPE_CHARBUF_LEN, 1, 100,
				STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
						vmApiQueryDirectoryManagerLevelDmOutput,
						directoryManagerLevel) }, { APITYPE_CHARBUF_COUNT, 1,
				100, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
						vmApiQueryDirectoryManagerLevelDmOutput,
						directoryManagerLevelLength) }, { APITYPE_END_OF_TABLE,
				0, 0, 0, 0 } };

int smQuery_Directory_Manager_Level_DM(
		struct _VmApiInternalContext* vmapiContextP, char * userid,
		int passwordLength, char * password, char * targetIdentifier,
		vmApiQueryDirectoryManagerLevelDmOutput ** outData);

#ifdef __cplusplus
}
#endif

#endif
