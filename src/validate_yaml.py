from typing import List

def _validate_type(value: any, expected_type: str) -> bool:    
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

def _validate_job(job_name: str, job_config: dict, schema: dict, defaults: dict) -> List[str]:
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
    job_schema_arguments = schema[job_type]. get("arguments", {}).items()

    for argument_name, argument_schema in job_schema_arguments:
        is_required = argument_schema.get("required", False)
        value = job_arguments.get(argument_name, defaults.get(argument_name))

        if value is None and is_required:
            errors.append(f"[{job_name}] Missing required argument '{argument_name}'.")
        elif value is not None:
            if not _validate_type(value, argument_schema["type"]):
                errors.append(f"[{job_name}] Invalid type for argument '{argument_name}' the argument is expected to have the following type '{argument_schema['type']}'.")
            if "options" in argument_schema and value not in argument_schema["options"]:
                errors.append(f"[{job_name}] Invalid option '{value}' for argument '{argument_name}', must be one of the following values '{'\', \''.join(argument_schema['options'])}'.")

    return errors

def validate_jobs(input_yaml: dict, schema_yaml: dict) -> List[str]:
    validation_errors = []

    defaults = input_yaml.get("defaults", {})
    jobs = input_yaml.get("jobs", {})

    if not isinstance(jobs, dict):
        return ["The 'jobs' key must be a map."]
    
    if jobs == {}:
        return ["There are no jobs to process, make sure the different jobs are defined in a map."]
    
    for job_name, job_config in jobs.items():
        job_errors = _validate_job(job_name, job_config, schema_yaml, defaults)
        validation_errors.extend(job_errors)

    return validation_errors
