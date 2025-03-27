import { Component, OnInit, ViewChild, ElementRef } from '@angular/core';
import { ApiService } from '../api.service';

import {
  UntypedFormBuilder,
  FormControl,
  UntypedFormGroup,
  Validators
} from '@angular/forms';
import { FormsModule, ReactiveFormsModule } from '@angular/forms';

@Component({
    selector: 'app-manage-dhcp-pools',
    templateUrl: './manage-dhcp-pools.component.html',
    styleUrls: ['./manage-dhcp-pools.component.scss'],
    standalone: false
})
export class ManageDhcpPoolsComponent implements OnInit {
  pool;
  pools;
  errors;
  form: UntypedFormGroup;
  showPoolModalMode = "";

  constructor(
    private apiService: ApiService,
    private formBuilder: UntypedFormBuilder
  ) {
    this.form = this.formBuilder.group({
      net_address: ['', [Validators.required]],
      netmask: ['', [Validators.required]],
      name: ['', [Validators.required]],
      start_address: ['', [Validators.required]],
      end_address: ['', [Validators.required]],
      gateway: ['', [Validators.required]],
    });
  }

  ngOnInit(): void {
    this.apiService.getPools().subscribe((data: any) => {
      this.pools = data;
    });
  }


  showPoolModal(mode, id = null) {
    this.showPoolModalMode = mode;
    if (mode === "edit") {
      this.pool = this.pools.find(pool => pool.id === id);
      this.form.patchValue({
        ...this.pool,
      });
    }
    if (mode === "add") {
      this.form.reset();
    }
  }


    @ViewChild('fileInput') fileInput!: ElementRef;
  
    triggerFileInput() {
      this.fileInput.nativeElement.click();
    }
  
    handleFileUpload(event: Event) {
      const target = event.target as HTMLInputElement;
      if (target.files && target.files.length > 0) {
        const file = target.files[0];
        console.log('Selected file:', file.name);
        
        // Process the file (e.g., read content)
        this.readCSVFile(file);
      }
    }
  
    readCSVFile(file: File) {
      const reader = new FileReader();
      reader.onload = (e) => {

        const csvContent = e.target?.result as string;
        console.log('CSV Content:', csvContent);
        const parsedData = this.parseCSV(csvContent);
        this.uploadPools(parsedData);
      };
      reader.readAsText(file);
    }

  // Sends parsed data to API using ApiService
  uploadPools(pools: any[]) {
    pools.forEach((pool) => {
      console.log(pool)
      var data = {
        ...pool,
        only_serve_reimage: true,
        lease_time: 7000,
      };
      this.apiService.addPool(data).subscribe({
        next: (resp: any) => {
          if (resp.error) {
            this.errors = resp.error;
          } else {
            this.pools.push(resp);
            this.form.reset();
          }
        },
        error: (err) => {
          console.error('API error:', err);
          this.errors = err;
        }
      });
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
          
          // Check if the header is 'netmask' and parse it to an integer
          if (header === 'netmask' && value !== '') {
            formGroup[header] = parseInt(value, 10); // Convert netmask to integer
          } else {
            formGroup[header] = value;
          }

          
        });

        // Push the formGroup into the data array
        data.push(formGroup);
      }
    }
    return data;
  }
    
  

  submit() {
    const data = {
      ...this.form.value,
      only_serve_reimage: true,
      lease_time: 7000,
    };

    this.apiService.addPool(data).subscribe((resp: any) => {
      if (resp.error) {
        this.errors = resp.error;
      }
      if (resp) {
        this.pools.push(resp);
        this.form.reset();
      }
    });

    this.showPoolModalMode = '';
  }

  remove(id) {
    this.apiService.deletePool(id).subscribe((data: any) => {
      this.pools = this.pools.filter(item => item.id !== id);
    }, (data: any) => {
      if (data.error) {
        this.errors = [data.error];
      }
    });
  }

  updatePool() {
    const data = {
      ...this.form.value,
      only_serve_reimage: true,
      lease_time: 7000,
    };

    this.apiService.updatePool(this.pool.id, data).subscribe((resp: any) => {
      if (resp.error) {
        this.errors = resp.error;
      }
      if (resp) {
        this.pools = this.pools.filter(item => item.id !== resp.id);
        this.pools.push(resp);
        this.showPoolModalMode = '';
      }
    });
  }
}
