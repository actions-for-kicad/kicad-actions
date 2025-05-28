import os
import sys
import yaml

def load_yaml_from_env():
    # Get the file path from the environment variable
    input_file = os.getenv("INPUT_INPUT_FILE")

    if not input_file:
        print("Error: Environment variable 'INPUT_INPUT_FILE' is not set.", file=sys.stderr)
        sys.exit(1)

    # Check if the file exists
    if not os.path.isfile(input_file):
        print(f"Error: File '{input_file}' does not exist.", file=sys.stderr)
        sys.exit(1)

    try:
        # Open and load YAML
        with open(input_file, 'r') as f:
            data = yaml.safe_load(f)
            if not isinstance(data, dict):
                print("Error: YAML content is not a dictionary.", file=sys.stderr)
                sys.exit(1)
            return data
    except yaml.YAMLError as e:
        print(f"Error: Failed to parse YAML file. Details:\n{e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    result = load_yaml_from_env()
    print("YAML successfully loaded into dictionary:")
    print(result)
