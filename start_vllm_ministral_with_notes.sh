#!/bin/bash
# Note: This model may require a newer version of transformers that supports ministral3
# If you encounter KeyError: 'ministral3', try:
#   1. Upgrade transformers: pip install --upgrade transformers>=4.50.0
#   2. Or use Docker: docker run --gpus all -p 8000:8000 vllm/vllm-openai:latest --model pankajmathur/ministral3-3b-sft-openthoughts-merged

./start_vllm_ministral.sh "$@"
