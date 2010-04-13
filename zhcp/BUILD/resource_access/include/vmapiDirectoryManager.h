// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#ifndef _VMAPI_DIRECTORY_MANAGER_H
#define _VMAPI_DIRECTORY_MANAGER_H
#include "smPublic.h"
#include "smapiTableParser.h"
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Directory_Manager_Local_Tag_Define_DM
typedef commonOutputFields vmApiDirectoryManagerLocalTagDefineDmOutput;

// Parser table for Directory_Manager_Local_Tag_Define_DM
static tableLayout Directory_Manager_Local_Tag_Define_DM_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiDirectoryManagerLocalTagDefineDmOutput) }, { APITYPE_INT4,
		4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiDirectoryManagerLocalTagDefineDmOutput, requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiDirectoryManagerLocalTagDefineDmOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiDirectoryManagerLocalTagDefineDmOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int smDirectory_Manager_Local_Tag_Define_DM(
		struct _VmApiInternalContext* vmapiContextP, char * userid,
		int passwordLength, char * password, char * targetIdentifier,
		char * tag_name, int tag_ordinal, char createOrChange,
		vmApiDirectoryManagerLocalTagDefineDmOutput ** outData);

// Directory_Manager_Local_Tag_Delete_DM
typedef commonOutputFields vmApiDirectoryManagerLocalTagDeleteDmOutput;

// Parser table for Directory_Manager_Local_Tag_Delete_DM
static tableLayout Directory_Manager_Local_Tag_Delete_DM_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiDirectoryManagerLocalTagDeleteDmOutput) }, { APITYPE_INT4,
		4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiDirectoryManagerLocalTagDeleteDmOutput, requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiDirectoryManagerLocalTagDeleteDmOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiDirectoryManagerLocalTagDeleteDmOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int
		smDirectory_Manager_Local_Tag_Delete_DM(
				struct _VmApiInternalContext* vmapiContextP, char * userid,
				int passwordLength, char * password, char * targetIdentifier,
				char * tag_name,
				vmApiDirectoryManagerLocalTagDeleteDmOutput ** outData);

// Directory_Manager_Local_Tag_Query_DM
typedef struct _vmApiDirectoryManagerLocalTagQueryDmOutput {
	commonOutputFields common;
	int tagValueLength;
	char * tagValue;
} vmApiDirectoryManagerLocalTagQueryDmOutput;

// Parser table for Directory_Manager_Local_Tag_Query_DM
static tableLayout
		Directory_Manager_Local_Tag_Query_DM_Layout = { {
				APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
				sizeof(vmApiDirectoryManagerLocalTagQueryDmOutput) }, {
				APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
						vmApiDirectoryManagerLocalTagQueryDmOutput,
						common.requestId) }, { APITYPE_INT4, 4, 4,
				STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
						vmApiDirectoryManagerLocalTagQueryDmOutput,
						common.returnCode) }, { APITYPE_INT4, 4, 4,
				STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
						vmApiDirectoryManagerLocalTagQueryDmOutput,
						common.reasonCode) },
				{ APITYPE_CHARBUF_LEN, 1, 240, STRUCT_INDX_0, NEST_LEVEL_0,
						offsetof(vmApiDirectoryManagerLocalTagQueryDmOutput,
								tagValue) }, { APITYPE_CHARBUF_COUNT, 4, 4,
						STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
								vmApiDirectoryManagerLocalTagQueryDmOutput,
								tagValueLength) }, { APITYPE_END_OF_TABLE, 0,
						0, 0, 0 } };
int smDirectory_Manager_Local_Tag_Query_DM(
		struct _VmApiInternalContext* vmapiContextP, char * userid,
		int passwordLength, char * password, char * targetIdentifier,
		char * tag_name, vmApiDirectoryManagerLocalTagQueryDmOutput ** outData);

// Directory_Manager_Local_Tag_Set_DM
typedef commonOutputFields vmApiDirectoryManagerLocalTagSetDmOutput;

// Parser table for Directory_Manager_Local_Tag_Set_DM
static tableLayout Directory_Manager_Local_Tag_Set_DM_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiDirectoryManagerLocalTagSetDmOutput) }, { APITYPE_INT4, 4,
		4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiDirectoryManagerLocalTagSetDmOutput, requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiDirectoryManagerLocalTagSetDmOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiDirectoryManagerLocalTagSetDmOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int smDirectory_Manager_Local_Tag_Set_DM(
		struct _VmApiInternalContext* vmapiContextP, char * userid,
		int passwordLength, char * password, char * targetIdentifier,
		char * tag_name, int tag_value_length, char * tag_value,
		vmApiDirectoryManagerLocalTagSetDmOutput ** outData);

// Directory_Manager_Search_DM
typedef struct _vmApiDirectoryManagerStatement { // Common structure used by Directory_Manager_Search
	char * targetId;
	int statementLength;
	char * statement;
} vmApiDirectoryManagerStatement;

typedef struct _vmApiDirectoryManagerSearchDmOutput {
	commonOutputFields common;
	int statementCount;
	vmApiDirectoryManagerStatement * statementList;
} vmApiDirectoryManagerSearchDmOutput;

// Parser table for Directory_Manager_Search_DM
static tableLayout Directory_Manager_Search_DM_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiDirectoryManagerSearchDmOutput) }, { APITYPE_INT4, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiDirectoryManagerSearchDmOutput, common.requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiDirectoryManagerSearchDmOutput, common.returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiDirectoryManagerSearchDmOutput, common.reasonCode) },

{ APITYPE_ARRAY_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
		vmApiDirectoryManagerSearchDmOutput, statementList) }, {
		APITYPE_ARRAY_STRUCT_COUNT, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		offsetof(vmApiDirectoryManagerSearchDmOutput, statementCount) }, {
		APITYPE_NOBUFFER_STRUCT_LEN, 4, 4, STRUCT_INDX_1, NEST_LEVEL_1,
		sizeof(vmApiDirectoryManagerStatement) }, { APITYPE_STRING_LEN, 1, 8,
		STRUCT_INDX_1, NEST_LEVEL_1, offsetof(vmApiDirectoryManagerStatement,
				targetId) }, { APITYPE_CHARBUF_LEN, 1, 72, STRUCT_INDX_1,
		NEST_LEVEL_1, offsetof(vmApiDirectoryManagerStatement, statement) }, {
		APITYPE_CHARBUF_COUNT, 0, 4, STRUCT_INDX_1, NEST_LEVEL_1, offsetof(
				vmApiDirectoryManagerStatement, statementLength) },

{ APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int smDirectory_Manager_Search_DM(struct _VmApiInternalContext* vmapiContextP,
		char * userid, int passwordLength, char * password,
		char * targetIdentifier, int search_pattern_length,
		char * search_pattern, vmApiDirectoryManagerSearchDmOutput ** outData);

// Directory_Manager_Task_Cancel_DM
typedef commonOutputFields vmApiDirectoryManagerTaskCancelDmOutput;

//  Parser table for Directory_Manager_Task_Cancel_DM
static tableLayout Directory_Manager_Task_Cancel_DM_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiDirectoryManagerTaskCancelDmOutput) }, { APITYPE_INT4, 4,
		4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiDirectoryManagerTaskCancelDmOutput, requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiDirectoryManagerTaskCancelDmOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiDirectoryManagerTaskCancelDmOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int smDirectory_Manager_Task_Cancel_DM(
		struct _VmApiInternalContext* vmapiContextP, char * userid,
		int passwordLength, char * password, char * targetIdentifier,
		int operation_id, vmApiDirectoryManagerTaskCancelDmOutput ** outData);

#ifdef __cplusplus
}
#endif

#endif
