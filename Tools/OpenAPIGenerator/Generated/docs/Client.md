# Client

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**createdAt** | **Date** | The date the client was created. | [readonly] 
**elevatedUntil** | **Date** | The time until which this client&#39;s session is elevated. | [optional] [readonly] 
**expiresAfterInactivitySeconds** | **Int64** | The number of seconds of inactivity after which the client is removed. 0 means the client never expires. | [optional] 
**expiresAt** | **Date** | The time at which this client will expire due to inactivity, or null if it never expires. | [optional] [readonly] 
**id** | **Int64** | The client id. | [readonly] 
**lastUsed** | **Date** | The last time the client token was used. | [optional] [readonly] 
**name** | **String** | The client name. This is how the client should be displayed to the user. | 
**token** | **String** | The client token. Can be used as &#x60;clientToken&#x60;. See Authentication. | [optional] [readonly] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


