import { CommonModule } from '@angular/common';
import { Component, ElementRef, OnInit, ViewChild, AfterViewInit, AfterViewChecked } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ApiService } from '../api.service';
import { ClrFormsModule, ClrWizard, ClrWizardModule, ClarityModule } from '@clr/angular';

@Component({
  selector: 'app-host-deployment',
  templateUrl: './host-deployment.component.html',
  styleUrls: ['./host-deployment.component.scss'],
  standalone: true,
  imports: [CommonModule, ClrWizardModule, ClrFormsModule, FormsModule, ClarityModule], // Ensure FormsModule is included
})
export class HostDeploymentComponent implements OnInit {
  @ViewChild('wizard', { static: true }) wizard: ClrWizard | undefined;
  @ViewChild('fileInput', { static: false }) fileInput!: ElementRef;
  constructor(
      private apiService: ApiService,

    ) {};
  open = false;
  model: any;
  loadingFlag = false;
  errorFlag = false;


  ngOnInit() {
    this.model = {
      forceReset: true,
      useSameCreds: false,
      favoriteColor: '',
      luckyNumber: '',
      flavorOfIceCream: '',
      hosts: [],
      errors: [],
      selectVendor: '',
      iloPort: 443,
      setIloPort: false,
    };

  }

  selectVendor(vendor: string): void {
    this.model.selectedVendor = vendor;
    console.log('Selected vendor:', vendor);
  }

  doCancel(): void {
    this.doFinish();
    this.wizard?.reset(); // Explicitly reset the wizard
    this.open = false; // Close the wizard
  }
  doFinish(): void {
    this.doReset();
  }

  newHostInput: any = { iloIpAddr: '', username: '', password: '' };
  addHost(): void {
    // Ensure the hosts array exists
    if (!Array.isArray(this.model.hosts)) {
      this.model.hosts = [];
    }


    console.log(this.newHostInput);

    // Add the new host to the hosts array
    this.model.hosts.push({
      iloIpAddr: this.newHostInput.iloIpAddr,
      username: this.newHostInput.username,
      password: this.newHostInput.password,
    });

    // Reset the input fields for the next host
    this.newHostInput = { iloIpAddr: '', username: '', password: '' };

    console.log(this.model.hosts);
  }

  editHost(index: number): void {
    const host = this.model.hosts[index];
    this.newHostInput = { ...host }; // Populate input fields with the selected host's data
    this.removeHost(index); // Remove the host temporarily to allow editing
  }

  removeHost(index: number): void {
    this.model.hosts.splice(index, 1); // Remove the host at the specified index
  }

  doReset(): void {

      this.wizard?.reset();
      this.model.forceReset = true;
      this.model.favoriteColor = '';
      this.model.luckyNumber = '';
      this.model.flavorOfIceCream = '';
      this.loadingFlag = false;
      this.errorFlag = false;
      this.model.hosts = [];
      this.model.errors = [];
      this.model.selectedVendor = '';
      this.model.useSameCreds = false;
      this.model.iloPort = 443;
      this.model.setIloPort = false;
    
  }


  // IMPORT
  // import funcs to handle bulk import of hosts

  triggerFileInput(): void {
    if (this.fileInput) {
      // Reset the file input value to ensure the change event is triggered
      this.fileInput.nativeElement.value = '';
      this.fileInput.nativeElement.click();
    } else {
      console.error('fileInput is not available. Ensure the wizard is open and the element is rendered.');
    }
  }

  importHostsFromCSVToGroup(event: Event): void {
    console.log('Importing hosts from CSV to group');
    const target = event.target as HTMLInputElement;
  
    if (target.files && target.files.length > 0) {
      const file = target.files[0];
      console.log('Selected file:', file.name);
  
      // Call readCSVFile and handle the Promise
      this.readCSVFile(file)
        .then((parsedData) => {
          console.log('Parsed Host Data:', parsedData);
  
          parsedData.forEach((host) => {
            // Add the new host to the hosts array
            this.model.hosts.push({
              iloIpAddr: host.iloIpAddr,
              username: host.username,
              password: host.password,
            });
  
            console.log(this.model.hosts);
          });
        })
        .catch((error) => {
          console.error('Error:', error);
          // Handle error, such as showing a notification to the user
        });
    }
  }

  readCSVFile(file: File): Promise<any[]> {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();

      reader.onload = (e) => {
        const csvContent = e.target?.result as string;

        try {
          const parsedData = this.parseCSV(csvContent);
          resolve(parsedData); // Resolve with parsed data
        } catch (error) {
          reject('Error parsing CSV: ' + error); // Reject if there's an error parsing
        }
      };

      reader.onerror = (error) => {
        reject('Error reading file: ' + error); // Reject if there's an error reading the file
      };

      reader.readAsText(file);
    });
  }
  // Parses CSV string into an array of objects matching the form structure
  parseCSV(csv: string): any[] {
    const lines = csv.split('\n').map(line => line.trim()).filter(line => line);
    const headers = lines[0].split(',').map(h => h.trim()); // Extract headers

    const data: any[] = [];

    for (let i = 1; i < lines.length; i++) {
      const values = lines[i].split(',').map(v => v.trim());
      if (values.length === headers.length) {
        const formGroup = {};

        // Dynamically map values to the formGroup based on the header fields
        headers.forEach((header, index) => {
          let value = values[index] || ''; // Default to empty string if no value
          formGroup[header] = value;

        });

        // Push the formGroup into the data array
        data.push(formGroup);
      }
    }
    return data;
  }

  // END IMPORT

  // VALIDATE

  async onCommit(): Promise<void> {
    this.loadingFlag = true;
    this.errorFlag = false;
  
    console.log(this.model.hosts);
  
    // Clear previous errors
    this.model.errors = [];

    // Ensure a vendor has been chosen
    if (!this.model.selectedVendor) {
      this.model.errors.push({
        subject: 'Vendor',
        message: 'Please select a vendor before proceeding.',
      });
    }

    for (const host of this.model.hosts) {
      await this.validateHost(host); // Wait for each host validation to complete
    }

    console.log('Validation done');
    console.log(this.model.errors);

    this.loadingFlag = false;



    // Set error flag if there are errors
    if (this.model.errors.length > 0) {
      this.errorFlag = true;
    } else {
      this.wizard?.next();
    }
  }

  validateHost(host: any): Promise<void> {
    return new Promise((resolve) => {

        console.log('Validating host ilo ip addr:', host.iloIpAddr);
  
        this.apiService.checkILOM(host.iloIpAddr, this.model.iloPort).subscribe({
          next: (resp: any) => {        

            console.log('Response:', resp);
            if (resp.error) {
              this.model.errors.push({
                subject: host.iloIpAddr,
                message: resp.error,
              });
            }
            resolve(); // Resolve the promise after validation is complete
          },
          error: (err: any) => {
            console.error('Error:', err.error.message ?? err);
            this.model.errors.push({
              subject: host.iloIpAddr,
              message: err.error.message,
            });
            resolve(); // Resolve even if there's an error
          }
        });

    });
  }
  
}


