import typing
import warnings
from enum import Enum

import orjson
from attrs import define
from pydantic import BaseModel, field_validator
from pydantic.fields import Field

warnings.simplefilter("ignore")


def orjson_dumps(v: typing.Any, *, default: typing.Any) -> typing.Any:
    # orjson.dumps returns bytes, to match standard json.dumps we need to decode
    return orjson.dumps(v, default=default).decode()


class Tags(Enum):
    """Tags for endpoints.

    Fields
    ======
        text_inference: endpoint for llm text inference
    """

    text_inference = "text_inference"


class BaseRequest(BaseModel):
    """Base request body from client.

    Fields
    ======
        data: dict
            Request body in JSON format.
    """

    data: dict[str, typing.Any] = Field(default='{"human_message": ""}')

    @field_validator("data")
    def validate_data(cls, v: typing.Any) -> typing.Any:
        return v

    @define(slots=True)
    class Config:
        title = "Base request data model for API."
        validate_all = False
        validate_assignment = False
        allow_mutation = True
        underscore_attrs_are_private = True
        anystr_stripe_whitespace = False
        arbitrary_types_allowed = False
        copy_on_model_validation = "shallow"
        # Does not support compound types yet, Union[list[str], list[int]].
        smart_union = True
        # Set to False for compatibility with JSON.
        allow_inf_nan = False
        json_loads = orjson.loads
        json_dumps = orjson_dumps


class BaseResponse(BaseModel):
    """Base response body from API.

    Fields
    ======
        data: dict
            Response body in JSON format.
    """

    data: typing.Optional[typing.Any] = Field(None)

    @field_validator("data")
    def validate_data(cls, v: typing.Any) -> typing.Any:
        return v

    @define(slots=True)
    class Config:
        title = "Base response data model for API."
        validate_all = False
        validate_assignment = False
        allow_mutation = True
        underscore_attrs_are_private = True
        anystr_stripe_whitespace = False
        arbitrary_types_allowed = False
        copy_on_model_validation = "shallow"
        # Does not support compound types yet, Union[list[str], list[int]].
        smart_union = True
        # Set to False for compatibility with JSON.
        allow_inf_nan = False
        json_loads = orjson.loads
        json_dumps = orjson_dumps
