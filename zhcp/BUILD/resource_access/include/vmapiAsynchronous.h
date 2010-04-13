// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#ifndef _VMAPI_ASYNCHRONOUS_H
#define _VMAPI_ASYNCHRONOUS_H
#include "smPublic.h"
#include "smapiTableParser.h"
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Asynchronous_Notification_Disable_DM
typedef commonOutputFields vmApiAsynchronousNotificationDisableDmOutput;

// Parser table for Asynchronous_Notification_Disable_DM
static tableLayout Asynchronous_Notification_Disable_DM_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiAsynchronousNotificationDisableDmOutput) }, { APITYPE_INT4,
		4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiAsynchronousNotificationDisableDmOutput, requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiAsynchronousNotificationDisableDmOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiAsynchronousNotificationDisableDmOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int smAsynchronous_Notification_Disable_DM(
		struct _VmApiInternalContext* vmapiContextP, char * userid,
		int passwordLength, char * password, char * targetIdentifier,
		char entity_type, char communication_type, int port_number,
		char * ip_address, char encoding, int subscriber_data_length,
		char * subscriber_data,
		vmApiAsynchronousNotificationDisableDmOutput ** outData);

// Asynchronous_Notification_Enable_DM
typedef commonOutputFields vmApiAsynchronousNotificationEnableDmOutput;

// Parser table for Asynchronous_Notification_Enable_DM
static tableLayout Asynchronous_Notification_Enable_DM_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiAsynchronousNotificationEnableDmOutput) }, { APITYPE_INT4,
		4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiAsynchronousNotificationEnableDmOutput, requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiAsynchronousNotificationEnableDmOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiAsynchronousNotificationEnableDmOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int smAsynchronous_Notification_Enable_DM(
		struct _VmApiInternalContext* vmapiContextP, char * userid,
		int passwordLength, char * password, char * targetIdentifier,
		char entity_type, char subscription_type, char communication_type,
		int port_number, char * ip_address, char encoding,
		int subscriber_data_length, char * subscriber_data,
		vmApiAsynchronousNotificationEnableDmOutput ** outData);

// Asynchronous_Notification_Query_DM
typedef struct _vmApiNotification { // Common structure used by Asynchronous_Notification_Query
	char * userid;
	char subscriptionType;
	char communicationType;
	int portNumber;
	char * ipAddress;
	char encoding;
	int subscriberDataLength;
	char * subscriberData;
} vmApiNotification;

typedef struct _vmApiAsynchronousNotificationQueryDmOutput {
	commonOutputFields common;
	int notificationCount;
	vmApiNotification * notificationList;
} vmApiAsynchronousNotificationQueryDmOutput;

// Parser table for Asynchronous_Notification_Query_DM
static tableLayout
		Asynchronous_Notification_Query_DM_Layout = { {
				APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
				sizeof(vmApiAsynchronousNotificationQueryDmOutput) }, {
				APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
						vmApiAsynchronousNotificationQueryDmOutput,
						common.requestId) }, { APITYPE_INT4, 4, 4,
				STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
						vmApiAsynchronousNotificationQueryDmOutput,
						common.returnCode) }, { APITYPE_INT4, 4, 4,
				STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
						vmApiAsynchronousNotificationQueryDmOutput,
						common.reasonCode) },

				{ APITYPE_ARRAY_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
						offsetof(vmApiAsynchronousNotificationQueryDmOutput,
								notificationList) }, {
						APITYPE_ARRAY_STRUCT_COUNT, 4, 4, STRUCT_INDX_0,
						NEST_LEVEL_0, offsetof(
								vmApiAsynchronousNotificationQueryDmOutput,
								notificationCount) }, { APITYPE_STRUCT_LEN, 4,
						4, STRUCT_INDX_1, NEST_LEVEL_1,
						sizeof(vmApiNotification) }, { APITYPE_STRING_LEN, 4,
						4, STRUCT_INDX_1, NEST_LEVEL_1, offsetof(
								vmApiNotification, userid) }, { APITYPE_INT1,
						4, 4, STRUCT_INDX_1, NEST_LEVEL_1, offsetof(
								vmApiNotification, subscriptionType) }, {
						APITYPE_INT1, 4, 4, STRUCT_INDX_1, NEST_LEVEL_1,
						offsetof(vmApiNotification, communicationType) }, {
						APITYPE_INT4, 4, 4, STRUCT_INDX_1, NEST_LEVEL_1,
						offsetof(vmApiNotification, portNumber) }, {
						APITYPE_STRING_LEN, 4, 4, STRUCT_INDX_1, NEST_LEVEL_1,
						offsetof(vmApiNotification, ipAddress) }, {
						APITYPE_INT1, 4, 4, STRUCT_INDX_1, NEST_LEVEL_1,
						offsetof(vmApiNotification, encoding) }, {
						APITYPE_CHARBUF_LEN, 0, 64, STRUCT_INDX_1,
						NEST_LEVEL_1, offsetof(vmApiNotification,
								subscriberData) }, { APITYPE_CHARBUF_COUNT, 0,
						4, STRUCT_INDX_1, NEST_LEVEL_1, offsetof(
								vmApiNotification, subscriberDataLength) }, {
						APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int smAsynchronous_Notification_Query_DM(
		struct _VmApiInternalContext* vmapiContextP, char * userid,
		int passwordLength, char * password, char * targetIdentifier,
		char entity_type, char communication_type, int port_number,
		char * ip_address, char encoding, int subscriber_data_length,
		char * subscriber_data,
		vmApiAsynchronousNotificationQueryDmOutput ** outData);

#ifdef __cplusplus
}
#endif

#endif
