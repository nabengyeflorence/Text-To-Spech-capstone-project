"""
Lambda handler: POST JSON { "text": "...", "voice": "Joanna", "format": "mp3" }
Calls Amazon Polly, stores audio in S3, returns presigned URL.
"""
import os
import json
import boto3
import uuid
import logging
import base64

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3")
polly = boto3.client("polly")

S3_BUCKET = os.environ.get("S3_BUCKET")
PRESIGN_TTL = int(os.environ.get("AUDIO_EXPIRE_SECONDS", "3600"))

def lambda_handler(event, context):
    try:
        # API Gateway v2 sends body as string
        body = event.get("body") or "{}"
        data = json.loads(body)

        text = data.get("text")
        if not text:
            return _resp(400, {"error": "No text provided"})

        voice = data.get("voice", "Joanna")
        fmt = data.get("format", "mp3")

        if len(text) > 30000:
            return _resp(400, {"error": "Text too long (max 30000 chars). Please split."})

        # Polly synthesize
        output_format = fmt.lower()
        # Polly expects specific uppercase for some: mp3, ogg_vorbis, pcm
        if output_format == "ogg":
            output_format = "ogg_vorbis"
        response = polly.synthesize_speech(Text=text, VoiceId=voice, OutputFormat=output_format)

        audio_stream = response.get("AudioStream")
        if audio_stream is None:
            logger.error("No AudioStream in Polly response")
            return _resp(500, {"error": "Polly returned no audio"})

        ext = "mp3" if "mp3" in output_format else ("ogg" if "ogg" in output_format else "wav")
        key = f"tts-output/{uuid.uuid4()}.{ext}"

        # Read stream and upload
        body_bytes = audio_stream.read()
        s3.put_object(Bucket=S3_BUCKET, Key=key, Body=body_bytes, ContentType=_content_type_for_ext(ext))

        # Presigned URL
        url = s3.generate_presigned_url(
            "get_object",
            Params={"Bucket": S3_BUCKET, "Key": key},
            ExpiresIn=PRESIGN_TTL
        )

        return _resp(200, {"url": url, "key": key})
    except Exception as e:
        logger.exception("Error synthesizing speech")
        return _resp(500, {"error": str(e)})

def _content_type_for_ext(ext):
    return {
        "mp3": "audio/mpeg",
        "ogg": "audio/ogg",
        "wav": "audio/wav"
    }.get(ext, "application/octet-stream")

def _resp(status_code, body_dict):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type",
            "Access-Control-Allow-Methods": "POST, OPTIONS"
        },
        "body": json.dumps(body_dict)
    }
