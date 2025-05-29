from sys import exit

from src.load_yaml import load_schema_yaml, load_input_yaml_from_env
from src.validate_yaml import validate_jobs

if __name__ == "__main__":
    # Load the input YAML from environment variables and the schema YAML from a file
    input_yaml = load_input_yaml_from_env()
    schema_yaml = load_schema_yaml()

    # Validate the loaded YAML content
    validation_errors = validate_jobs(input_yaml, schema_yaml)

    if validation_errors:
        for error in validation_errors:
            print(f"::error:: {error}")
        exit(1)

    # Run the KiCad function for each job
    for job in input_yaml.get("jobs", []):
        pass

# TODO list
# main.py
# - [ ] Call load yaml function in different file
# - [X] Call validate yaml function in different file
# - [ ] Call kicad function in different file
#
# load_yaml.py
# - [ ] Load YAML from file
# - [ ] Load YAML from string
#
# validate_yaml.py
# - [X] Validate YAML content based on the mapping of KiCad commands
# - [X] Throw error if not valid
# - [X] Return dictionary if valid
#
# kicad.py
# - [ ] Loop through all YAML jobs
# - [ ] For every job, call the kicad function
# - [ ] Return the result file location of the kicad function