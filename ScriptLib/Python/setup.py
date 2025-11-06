from setuptools import setup, find_packages

setup(
    name='flrlib',
    version='0.1.0',
    description='An interface to script Fluorescence applications',
    author='Nithin Pranesh',
    author_email='',
    packages=find_packages(),
    install_requires=[
        'pywin32'
    ],
)