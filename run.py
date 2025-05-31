import yaml
from sys import exit
from os import path, getenv
from subprocess import run
from typing import List

def load_yaml_from_file(input_file: str) -> dict:
    if not path.isfile(input_file):
        print(f"::error::File '{input_file}' does not exist.")
        exit(1)
    
    with open(input_file) as f:
        return load_yaml_from_string(f)


def load_yaml_from_string(yaml_input: str) -> dict:
    try:
        return yaml.safe_load(yaml_input)
    except yaml.YAMLError as error:
        print(f"::error::Failed to parse YAML input, due to following error '{error}'.")
        exit(1)


def load_schema_yaml() -> dict:
    return load_yaml_from_file("commands-config.yml")


def load_input_yaml_from_env() -> dict:
    input_file = getenv("INPUT_INPUT_FILE")
    raw_input = getenv("INPUT_INPUT")

    if not input_file and not raw_input:
        print("::error::Provide a yaml input by using the 'input' input or a yaml file input by using the 'input_file' input.")
        exit(1)

    if input_file and raw_input:
        print("::warning::Both a yaml input and yaml file input are given, the yaml file input will be used.")

    if input_file:
        return load_yaml_from_file(input_file)

    return load_yaml_from_string(raw_input)


def validate_type(value: any, expected_type: str) -> bool:    
    match expected_type:
        case 'string':
            return isinstance(value, str)
        case 'integer':
            return isinstance(value, int)
        case 'boolean':
            return isinstance(value, bool)
        case 'map':
            return isinstance(value, dict)
        case _:
            return False


def run_kicad_command(command: str) -> List[str]:
    # print(command)
    result = run(["kicad-cli", command])

    if result.returncode != 0:
        return f"::error:: Command '{command}' failed with error: {result.stderr.strip()}"

    return []


def validate_job(job_name: str, job_config: dict, schema: dict, defaults: dict) -> List[str]:
    # Validate the job type
    job_type = job_config.get('type')
    if not job_type:
        return [f"[{job_name}] The 'type' key is not present in this job configuration. Please specify a valid job type."]
    
    if job_type not in schema:
        return [f"[{job_name}] The job type '{job_type}' is not a valid job type. Please provide one of the following types '{'\', \''.join(schema.keys())}'."]

    # Validate the job arguments map
    job_arguments = job_config.get("arguments", {})
    if not isinstance(job_arguments, dict):
        return [f"[{job_name}] The 'arguments' key must be a map. Please provide a valid map of arguments."]

    # Validate all job arguments against the schema
    errors = []
    job_schema_arguments = schema[job_type].get("arguments", {}).items()

    for argument_name, argument_schema in job_schema_arguments:
        is_required = argument_schema.get("required", False)
        value = job_arguments.get(argument_name, defaults.get(argument_name))

        if value is None and is_required:
            errors.append(f"[{job_name}] Missing required argument '{argument_name}'.")
            continue
        
        if value is not None:
            if not validate_type(value, argument_schema["type"]):
                errors.append(f"[{job_name}] Invalid type for argument '{argument_name}' the argument is expected to have the following type '{argument_schema['type']}'.")
            if "options" in argument_schema and value not in argument_schema["options"]:
                errors.append(f"[{job_name}] Invalid option '{value}' for argument '{argument_name}', must be one of the following values '{'\', \''.join(argument_schema['options'])}'.")

    return errors


def run_job(job_config: dict, schema: dict, defaults: dict) -> List[str]:
    # Validate all job arguments against the schema
    job_type = job_config.get('type')
    job_schema_arguments = schema[job_type].get("arguments", {}).items()
    job_arguments = job_config.get("arguments", {})

    positional_arguments = {}
    optional_arguments = []

    for argument_name, argument_schema in job_schema_arguments:
        position = argument_schema.get("position", None)
        value = job_arguments.get(argument_name, defaults.get(argument_name))

        if position is not None:
            positional_arguments[position] = value
        else:
            if value is None:
                continue

            match argument_schema["type"]:
                case "boolean":
                    if value:
                        optional_arguments.append(f"--{argument_name}")
                case "string" | "integer":
                    optional_arguments.append(f"--{argument_name} {value}")
                case "map":
                    for key, val in value.items():
                        optional_arguments.append(f"--{argument_name} {key}={val}")
                case _:
                    continue

    # Run the KiCad command if the job type is a command
    errors = []

    if schema[job_type].get("type") == "command":
        positional_arguments_string = ' '.join(value for key, value in sorted(positional_arguments.items(), key=lambda x: int(x[0])))
        command = f"{schema[job_type].get('command')} "

        if optional_arguments:
            command += f"{' '.join(optional_arguments)} "
        
        if positional_arguments_string:
            command += f"{positional_arguments_string}"

        # Here you would normally run the command, but for validation, we just return the command
        errors.extend(run_kicad_command(command))

    elif schema[job_type].get("type") == "multiple":
        commands = schema[job_type].get("commands", [])
        for command in commands:
            errors.extend(run_job({"type": command, "arguments": job_arguments}, schema, defaults))

    return errors


def run_jobs(input_yaml: dict, schema_yaml: dict) -> None:
    errors = []

    defaults = input_yaml.get("defaults", {})
    jobs = input_yaml.get("jobs", {})

    if not isinstance(jobs, dict):
        return ["The 'jobs' key must be a map."]
    
    if jobs == {}:
        return ["There are no jobs to process, make sure the different jobs are defined in a map."]

    for job_name, job_config in jobs.items():
        job_validation_errors = validate_job(job_name, job_config, schema_yaml, defaults)
        errors.extend(job_validation_errors)
        job_errors = run_job(job_config, schema_yaml, defaults)
        errors.extend(job_errors)

    if errors:
        for error in errors:
            print(f"::error:: {error}")
        exit(1)


if __name__ == "__main__":
    # Load the input YAML from environment variables and the schema YAML from a file
    input_yaml = load_input_yaml_from_env()
    schema_yaml = load_schema_yaml()

    # Run the jobs from the loaded YAML content
    run_jobs(input_yaml, schema_yaml)
