# Dependencies

pip install --target=../build/dependencies requests
cd ../build/dependencies
zip -r ../mydeployment.zip .
cd ../lambda-s3-trigger-python/
zip ../build/mydeployment.zip main.py
