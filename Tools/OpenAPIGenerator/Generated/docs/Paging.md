# Paging

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**limit** | **Int64** | The limit of the messages for the current request. | [readonly] 
**next** | **String** | The relative path for the next page. Empty/Null when no next page is available. Should be combined with the gotify base url. | [optional] [readonly] 
**since** | **Int64** | The ID of the last message returned in the current request. Use this as alternative to the next link. | [readonly] 
**size** | **Int64** | The amount of messages that got returned in the current request. | [readonly] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


