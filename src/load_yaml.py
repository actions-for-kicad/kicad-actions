import yaml
from os import path, getenv
from sys import exit

def _load_yaml_from_file(input_file: str) -> dict:
    if not path.isfile(input_file):
        print(f"::error:: File '{input_file}' does not exist.")
        exit(1)
    
    with open(input_file) as f:
        return _load_yaml(f)
    
def _load_yaml(yaml_input: str) -> dict:
    try:
        return yaml.safe_load(yaml_input)
    except yaml.YAMLError as error:
        print(f"::error::Failed to parse YAML input, due to following error '{error}'.")
        exit(1)

def load_schema_yaml() -> dict:
    return _load_yaml_from_file("schema.yml")

def load_input_yaml_from_env() -> dict:
    input_file = getenv("INPUT_INPUT_FILE")
    raw_input = getenv("INPUT_INPUT")

    if not input_file and not raw_input:
        print("::error::Provide a yaml input by using the 'input' input or a yaml file input by using the 'input_file' input.")
        exit(1)

    if input_file and raw_input:
        print("::warning::Both a yaml input and yaml file input are given, the yaml file input will be used.")

    if input_file:
        return _load_yaml_from_file(input_file)

    return _load_yaml(raw_input)